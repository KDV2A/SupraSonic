import Foundation
import FluidAudio

// MARK: - Models

struct SpeakerProfile: Codable, Identifiable {
    let id: String           // UUID string
    var name: String
    var role: String
    var groupName: String    // e.g. "Marketing", "Engineering"
    var colorHex: String     // For avatar background
    var embedding: [Float]   // Voice embedding from FluidAudio
    let enrolledAt: Date
    var updatedAt: Date
    
    var initials: String {
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    init(name: String, role: String = "", groupName: String = "", colorHex: String = "#00E5FF", embedding: [Float]) {
        self.id = UUID().uuidString
        self.name = name
        self.role = role
        self.groupName = groupName
        self.colorHex = colorHex
        self.embedding = embedding
        self.enrolledAt = Date()
        self.updatedAt = Date()
    }
}

struct SpeakerGroup: Identifiable {
    let id: String  // Same as name for simplicity
    let name: String
    var members: [SpeakerProfile]
    
    init(name: String, members: [SpeakerProfile] = []) {
        self.id = name
        self.name = name
        self.members = members
    }
}

// MARK: - Manager

@MainActor
class SpeakerEnrollmentManager: ObservableObject {
    static let shared = SpeakerEnrollmentManager()
    
    @Published var profiles: [SpeakerProfile] = []
    @Published var isEnrolling = false
    @Published var enrollmentProgress: Double = 0
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Available colors for new speakers
    static let availableColors: [String] = [
        "#00E5FF", "#FF4081", "#7C4DFF", "#00C853",
        "#FFD740", "#FF6E40", "#448AFF", "#E040FB",
        "#64FFDA", "#FF5252", "#536DFE", "#B388FF"
    ]
    
    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SupraSonic")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("speakers_enrolled.json")
    }
    
    private init() {
        loadProfiles()
    }
    
    // MARK: - Persistence
    
    func loadProfiles() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            profiles = []
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            profiles = try decoder.decode([SpeakerProfile].self, from: data)
            print("👤 Enrollment: Loaded \(profiles.count) speaker profiles")
        } catch {
            print("❌ Enrollment: Failed to load profiles: \(error)")
            profiles = []
        }
    }
    
    private func saveProfiles() {
        do {
            let data = try encoder.encode(profiles)
            try data.write(to: storageURL)
            print("💾 Enrollment: Saved \(profiles.count) speaker profiles")
        } catch {
            print("❌ Enrollment: Failed to save profiles: \(error)")
        }
    }
    
    // MARK: - Enrollment
    
    /// Enroll a new speaker by extracting voice embedding from audio samples.
    /// Audio must be 16kHz mono Float32.
    func enrollSpeaker(name: String, role: String, groupName: String, audioSamples: [Float]) async throws -> SpeakerProfile {
        guard audioSamples.count >= 16000 * 3 else {
            throw EnrollmentError.insufficientAudio
        }
        
        isEnrolling = true
        enrollmentProgress = 0.2
        
        defer {
            isEnrolling = false
            enrollmentProgress = 0
        }
        
        // Ensure diarizer models are available
        guard TranscriptionManager.shared.diarizerModels != nil else {
            throw EnrollmentError.modelsNotLoaded
        }
        
        enrollmentProgress = 0.4
        
        // Extract embedding using FluidAudio
        let diarizer = DiarizerManager()
        diarizer.initialize(models: TranscriptionManager.shared.diarizerModels!)
        
        enrollmentProgress = 0.6
        
        // Normalize audio to help VAD (Voice Activity Detection)
        // Boost quiet speech to 0.9 peak amplitude
        let maxAmp = audioSamples.reduce(0) { max($0, abs($1)) }
        let scale = maxAmp > 0 ? 0.9 / maxAmp : 1.0
        // Clamp scale to avoid massive noise amplification if signal is tiny (though silence check prevents that)
        let safeScale = min(scale, 100.0) 
        let normalizedSamples = audioSamples.map { $0 * safeScale }
        
        print("📊 Enrollment: Normalizing audio. MaxAmp: \(maxAmp) -> scaled by \(safeScale)")
        
        // Get the embedding from diarization result
        let result = try diarizer.performCompleteDiarization(normalizedSamples)
        
        print("📊 Enrollment Debug: Segments found: \(result.segments.count)")
        if let db = result.speakerDatabase {
            print("📊 Enrollment Debug: Speakers found: \(db.keys.joined(separator: ", "))")
        } else {
            print("📊 Enrollment Debug: No speaker database returned")
        }
        
        guard let speakerDB = result.speakerDatabase, let firstEmbedding = speakerDB.values.first else {
            print("❌ Enrollment Debug: Embedding extraction failed. Audio length: \(normalizedSamples.count)")
            throw EnrollmentError.embeddingFailed
        }
        
        enrollmentProgress = 0.9
        
        // Pick a color that isn't already heavily used
        let usedColors = profiles.map { $0.colorHex }
        let color = Self.availableColors.first(where: { c in usedColors.filter({ $0 == c }).count < 2 }) ?? Self.availableColors.randomElement()!
        
        let profile = SpeakerProfile(
            name: name,
            role: role,
            groupName: groupName,
            colorHex: color,
            embedding: firstEmbedding
        )
        
        profiles.append(profile)
        saveProfiles()
        
        enrollmentProgress = 1.0
        print("✅ Enrollment: Enrolled '\(name)' with \(firstEmbedding.count)-dim embedding")
        
        return profile
    }
    
    /// Re-enroll: update the voice embedding for an existing speaker
    func reEnroll(profileId: String, audioSamples: [Float]) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw EnrollmentError.profileNotFound
        }
        
        guard audioSamples.count >= 16000 * 3 else {
            throw EnrollmentError.insufficientAudio
        }
        
        guard TranscriptionManager.shared.diarizerModels != nil else {
            throw EnrollmentError.modelsNotLoaded
        }
        
        isEnrolling = true
        defer { isEnrolling = false }
        
        let diarizer = DiarizerManager()
        diarizer.initialize(models: TranscriptionManager.shared.diarizerModels!)
        
        let result = try diarizer.performCompleteDiarization(audioSamples)
        
        guard let speakerDB = result.speakerDatabase, let newEmbedding = speakerDB.values.first else {
            throw EnrollmentError.embeddingFailed
        }
        
        profiles[index].embedding = newEmbedding
        profiles[index].updatedAt = Date()
        saveProfiles()
        
        print("🔄 Enrollment: Re-enrolled '\(profiles[index].name)' with fresh embedding")
    }
    
    // MARK: - CRUD
    
    func updateProfile(id: String, name: String?, role: String?, groupName: String?) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { profiles[index].name = name }
        if let role = role { profiles[index].role = role }
        if let groupName = groupName { profiles[index].groupName = groupName }
        profiles[index].updatedAt = Date()
        saveProfiles()
    }
    
    func deleteProfile(id: String) {
        profiles.removeAll { $0.id == id }
        saveProfiles()
    }
    
    // MARK: - Groups
    
    /// Returns profiles organized by group name
    var groupedProfiles: [SpeakerGroup] {
        let dict = Dictionary(grouping: profiles) { $0.groupName.isEmpty ? "Sans groupe" : $0.groupName }
        return dict.map { SpeakerGroup(name: $0.key, members: $0.value) }
            .sorted { $0.name < $1.name }
    }
    
    /// Returns all unique group names
    var allGroupNames: [String] {
        let names = Set(profiles.map { $0.groupName.isEmpty ? "Sans groupe" : $0.groupName })
        return names.sorted()
    }
    
    // MARK: - Meeting Integration
    
    /// Load all enrolled speakers into a FluidAudio diarizer's SpeakerManager for known-speaker recognition.
    func loadKnownSpeakers(into diarizer: DiarizerManager) {
        guard !profiles.isEmpty else { return }
        
        let fluidSpeakers = profiles.map { profile in
            Speaker(id: profile.id, name: profile.name, currentEmbedding: profile.embedding)
        }
        
        diarizer.speakerManager.initializeKnownSpeakers(fluidSpeakers)
        print("👥 Enrollment: Loaded \(fluidSpeakers.count) known speakers into diarizer")
    }
    
    /// Find a speaker profile by matching a FluidAudio speaker ID
    func findProfile(for speakerId: String) -> SpeakerProfile? {
        // FluidAudio returns our profile IDs when speakers are matched
        return profiles.first { $0.id == speakerId }
    }
}

// MARK: - Errors

enum EnrollmentError: LocalizedError {
    case insufficientAudio
    case modelsNotLoaded
    case embeddingFailed
    case profileNotFound
    
    var errorDescription: String? {
        switch self {
        case .insufficientAudio:
            return L10n.isFrench ? "Audio trop court (min 3 secondes)" : "Audio too short (min 3 seconds)"
        case .modelsNotLoaded:
            return L10n.isFrench ? "Modèles de diarisation non chargés" : "Diarization models not loaded"
        case .embeddingFailed:
            return L10n.isFrench ? "Impossible d'extraire l'empreinte vocale" : "Failed to extract voice embedding"
        case .profileNotFound:
            return L10n.isFrench ? "Profil non trouvé" : "Profile not found"
        }
    }
}
