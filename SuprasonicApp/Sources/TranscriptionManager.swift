import FluidAudio
import AVFoundation

@MainActor
class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    // Core Engine
    private var stream: AsyncThrowingStream<String, Error>?
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var asrManager: AsrManager?
    private var currentLanguage: String = "fr"
    
    // Backward compatibility for preWarm and transcribe
    private var fluidAsr: AsrManager? { return asrManager }
    
    // Diarization
    private(set) var diarizerModels: DiarizerModels?
    @Published var isLoading = false
    @Published var isReady = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    
    private var isInitializing = false
    
    private init() {}
    
    /// Initialize the Parakeet ASR engine
    func initialize(language: String = "fr", forceReload: Bool = false) async throws {
        if isReady && !forceReload {
            debugLog("✅ TranscriptionManager: Already ready and no force reload requested.")
            return
        }
        
        if isInitializing {
            debugLog("⚠️ TranscriptionManager: Already initializing, skipping...")
            return
        }
        
        isInitializing = true
        defer { isInitializing = false }
        
        isLoading = true
        statusMessage = L10n.isFrench ? "Initialisation..." : "Initializing..."
        progress = 0
        currentLanguage = language
        
        let targetModelURL = getModelDirectoryURL()
        debugLog("📂 TranscriptionManager: Target model path is \(targetModelURL.path)")
        
        // Always attempt to purge legacy directory to ensure branding purity
        purgeLegacyDirectory()
        
        // Start a background task to monitor progress if download is needed
        let monitoringTask = Task {
            while !Task.isCancelled && self.isLoading {
                if self.statusMessage.contains("Téléchargement") || self.statusMessage.contains("Downloading") {
                    // Monitor disk usage for download progress (40% - 80% range)
                    let currentSize = getModelsDirectorySize()
                    let targetSize: Double = 600 * 1024 * 1024 // 600MB estimate
                    let downloadProgress = min(Double(currentSize) / targetSize, 1.0)
                    self.progress = 0.4 + (downloadProgress * 0.4)
                } else if self.statusMessage.contains("Optimisation") || self.statusMessage.contains("Optimizing") {
                    // Progress from 80% to 95% during optimization
                    if self.progress < 0.95 {
                        self.progress += 0.005
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        
        defer { monitoringTask.cancel() }
        
        do {
            let models: AsrModels
            
            if FileManager.default.fileExists(atPath: targetModelURL.path) {
                debugLog("📂 TranscriptionManager: Model found at target path. Loading...")
                statusMessage = L10n.isFrench ? "Chargement des modèles..." : "Loading models..."
                progress = 0.45
                models = try await AsrModels.load(from: targetModelURL)
                progress = 0.75
            } else {
                debugLog("📂 TranscriptionManager: Model NOT found. Initializing download...")
                statusMessage = L10n.isFrench ? "Téléchargement..." : "Downloading..."
                progress = 0.4
                
                // This call might take a long time.
                // Map string version to FluidAudio enum
                let modelVersion: AsrModelVersion = {
                    switch Constants.targetModelVersion {
                    case "v3": return .v3
                    default: return .v3
                    }
                }()
                
                _ = try await AsrModels.downloadAndLoad(version: modelVersion)
                
                debugLog("📂 TranscriptionManager: Download complete. Migrating to SupraSonic folder...")
                statusMessage = L10n.isFrench ? "Organisation des fichiers..." : "Organizing files..."
                // Immediately migrate to SupraSonic folder and CLEAN UP FluidAudio
                try migrateModelToSupraSonic()
                
                // RELOAD from the final destination to ensure we have correct paths
                let finalModelURL = getModelDirectoryURL()
                debugLog("📂 TranscriptionManager: Reloading models from \(finalModelURL.path)...")
                models = try await AsrModels.load(from: finalModelURL)
            }
            
            debugLog("⚙️ TranscriptionManager: Initializing ASR Manager (Compilation)...")
            statusMessage = L10n.isFrench ? "Optimisation des modèles (cela peut prendre une minute)..." : "Optimizing models (this may take a minute)..."
            // Start at 82% and let monitoring task nudge it
            if progress < 0.82 { progress = 0.82 }
            
            let asrManager = AsrManager(config: .default)
            try await asrManager.initialize(models: models)
            
            debugLog("🔥🔥 TranscriptionManager: Pre-warming model...")
            statusMessage = L10n.isFrench ? "Finalisation..." : "Finalizing..."
            progress = 0.96
            
            let dummySamples = [Float](repeating: 0, count: 1600)
            _ = try? await asrManager.transcribe(dummySamples)
            
            // fluidAsr is a computed property, no need to assign
            self.asrManager = asrManager
            isReady = true
            isLoading = false
            statusMessage = L10n.isFrench ? "Prêt" : "Ready"
            progress = 1.0
            debugLog("✅ TranscriptionManager: Initialization complete")
            
            // Clean up old model versions to free disk space
            cleanupOldModels()
        } catch {
            debugLog("❌ TranscriptionManager: Initialization failed: \(error.localizedDescription)")
            isLoading = false
            isReady = false
            statusMessage = "\(L10n.isFrench ? "Erreur" : "Error"): \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Diarization
    
    func downloadDiarizerModels() async throws {
        guard diarizerModels == nil else { return }
        
        await MainActor.run {
            self.progress = 0.0
            self.statusMessage = L10n.isFrench ? "Téléchargement modèles diarisation..." : "Downloading diarization models..."
            self.isLoading = true
        }
        
        do {
            debugLog("👯‍♀️ TranscriptionManager: Downloading Diarizer models...")
            // The library handles downloading if needed
            let diarizerDir = Self.diarizerModelsDirectory()
            let models = try await DiarizerModels.downloadIfNeeded(to: diarizerDir)
            self.diarizerModels = models
            
            // Clean up legacy FluidAudio diarizer directory
            Self.migrateLegacyDiarizerModels()
            debugLog("✅ TranscriptionManager: Diarizer models ready")
            
            await MainActor.run {
                self.progress = 1.0
                self.statusMessage = L10n.isFrench ? "Prêt" : "Ready"
                self.isLoading = false
            }
        } catch {
            debugLog("❌ TranscriptionManager: Failed to download diarizer models: \(error)")
            await MainActor.run {
                self.statusMessage = L10n.isFrench ? "Erreur téléchargement" : "Download error"
                self.isLoading = false
            }
            throw error
        }
    }
    
    /// Pre-warm the engine (e.g., after system wake)
    func preWarm() {
        guard isReady, let fluidAsr = fluidAsr else { return }
        
        Task {
            debugLog("🔥 TranscriptionManager: Proactive pre-warm started...")
            // Perform a small dummy transcription to wake up GPU/Metal
            let dummySamples = [Float](repeating: 0, count: 3200) // 0.2s at 16kHz
            _ = try? await fluidAsr.transcribe(dummySamples)
            debugLog("✅ TranscriptionManager: Proactive pre-warm complete")
        }
    }

    private func getModelsDirectorySize() -> Int64 {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return 0
        }
        
        let paths = [
            appSupport.appendingPathComponent("SupraSonic/models"),
            appSupport.appendingPathComponent("FluidAudio/models")
        ]
        
        var totalSize: Int64 = 0
        for path in paths {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue {
                let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
                if let enumerator = fileManager.enumerator(at: path, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        if let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                           resourceValues.isRegularFile == true,
                           let fileSize = resourceValues.fileSize {
                            totalSize += Int64(fileSize)
                        }
                    }
                }
            }
        }
        return totalSize
    }
    
    private func getModelDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("SupraSonic/models/huggingface.co/mlx-community")
        
        // Ensure base directory exists
        if !fileManager.fileExists(atPath: baseDir.path) {
            try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        
        // Return the specific target model path
        let targetPath = baseDir.appendingPathComponent(Constants.targetModelName)
        debugLog("📂 TranscriptionManager: Looking for target model: \(targetPath.lastPathComponent)")
        return targetPath
    }
    
    /// Removes any model directories that don't match the current target model.
    private func cleanupOldModels() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("SupraSonic/models/huggingface.co/mlx-community")
        
        guard let contents = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        for url in contents {
            if url.hasDirectoryPath && url.lastPathComponent != Constants.targetModelName {
                debugLog("🧹 TranscriptionManager: Purging old model version: \(url.lastPathComponent)")
                try? fileManager.removeItem(at: url)
            }
        }
    }
    
    private func purgeLegacyDirectory() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacyDir = appSupport.appendingPathComponent("FluidAudio")
        
        if fileManager.fileExists(atPath: legacyDir.path) {
            debugLog("🧹 TranscriptionManager: Purging legacy FluidAudio directory...")
            try? fileManager.removeItem(at: legacyDir)
        }
    }
    
    private func migrateModelToSupraSonic() throws {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        
        // Source: FluidAudio default download path
        let sourceBase = appSupport.appendingPathComponent("FluidAudio/models/huggingface.co/mlx-community")
        
        // Destination: SupraSonic path
        let destBase = appSupport.appendingPathComponent("SupraSonic/models/huggingface.co/mlx-community")
        
        // Check if source exists
        guard fileManager.fileExists(atPath: sourceBase.path) else {
            debugLog("📂 Migration: Source directory not found (nothing downloaded?)")
            return
        }
        
        // Find any model directory in source
        let contents = try fileManager.contentsOfDirectory(at: sourceBase, includingPropertiesForKeys: nil)
        guard let modelDir = contents.first(where: { $0.hasDirectoryPath }) else {
            debugLog("📂 Migration: No model directory found in source")
            return
        }
        
        let modelName = modelDir.lastPathComponent
        debugLog("📂 Migration: Found model '\(modelName)'")
        
        let destModel = destBase.appendingPathComponent(modelName)
        
        if !fileManager.fileExists(atPath: destModel.path) {
            debugLog("📂 Migration: Moving \(modelName) to SupraSonic...")
            
            // Create parent directories
            try fileManager.createDirectory(at: destBase, withIntermediateDirectories: true)
            
            // Move the whole model folder
            try fileManager.moveItem(at: modelDir, to: destModel)
            
            debugLog("✅ Migration: Complete")
        } else {
            debugLog("📂 Migration: Destination already exists. Skipping.")
        }
        
        // Clean up legacy directory
        purgeLegacyDirectory()
    }
    
    /// Transcribe audio from samples
    func transcribe(audioSamples: [Float]) async throws -> String {
        guard isReady, let fluidAsr = fluidAsr else {
            throw TranscriptionError.notInitialized
        }
        
        let result = try await fluidAsr.transcribe(audioSamples)
        let processedText = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return applyVocabularyMapping(to: processedText)
    }
    
    private func applyVocabularyMapping(to text: String) -> String {
        let mapping = SettingsManager.shared.vocabularyMapping
        guard !mapping.isEmpty else { return text }
        
        var correctedText = text
        
        // Sort keys by length (descending) to avoid partial replacements of longer phrases
        let sortedKeys = mapping.keys.sorted { $0.count > $1.count }
        
        for spoken in sortedKeys {
            if let corrected = mapping[spoken] {
                // Use regex for case-insensitive whole-word replacement if possible, 
                // but simple string replacement is safer for generic phrases.
                // We do case-insensitive search but preserve general context.
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: spoken))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    correctedText = regex.stringByReplacingMatches(in: correctedText, options: [], range: NSRange(location: 0, length: correctedText.utf16.count), withTemplate: corrected)
                }
            }
        }
        
        return correctedText
    }
}

// MARK: - Errors

extension TranscriptionManager {
    /// Shared directory for all diarizer models (streaming + offline)
    static func diarizerModelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SupraSonic/models/diarizer")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// Migrate diarizer models from legacy FluidAudio directory to SupraSonic
    static func migrateLegacyDiarizerModels() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacyDir = appSupport.appendingPathComponent("FluidAudio/Models")
        
        guard fm.fileExists(atPath: legacyDir.path) else { return }
        
        let destDir = diarizerModelsDirectory()
        
        // Move contents from FluidAudio/Models/ to SupraSonic/models/diarizer/
        if let contents = try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil) {
            for item in contents {
                let dest = destDir.appendingPathComponent(item.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: item, to: dest)
                    debugLog("📂 Diarizer Migration: Moved \(item.lastPathComponent) to SupraSonic")
                }
            }
        }
        
        // Remove legacy FluidAudio directory entirely
        let fluidAudioRoot = appSupport.appendingPathComponent("FluidAudio")
        if fm.fileExists(atPath: fluidAudioRoot.path) {
            try? fm.removeItem(at: fluidAudioRoot)
            debugLog("🧹 Diarizer Migration: Removed legacy FluidAudio directory")
        }
    }
    
    /// Total size of all SupraSonic models on disk
    static func totalModelsSize() -> Int64 {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("SupraSonic/models")
        
        guard fm.fileExists(atPath: modelsDir.path) else { return 0 }
        
        var totalSize: Int64 = 0
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        if let enumerator = fm.enumerator(at: modelsDir, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                   values.isRegularFile == true,
                   let size = values.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        return totalSize
    }
    
    /// Delete all downloaded models
    static func deleteAllModels() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("SupraSonic/models")
        if fm.fileExists(atPath: modelsDir.path) {
            try? fm.removeItem(at: modelsDir)
            debugLog("🗑️ Deleted all SupraSonic models")
        }
    }
}

enum TranscriptionError: LocalizedError {
    case notInitialized
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Moteur de transcription non initialisé"
        case .transcriptionFailed(let reason):
            return "Transcription échouée: \(reason)"
        }
    }
}
