import FluidAudio
import AVFoundation

@MainActor
class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    private var fluidAsr: AsrManager?
    private var currentLanguage: String = "fr"
    
    @Published var isLoading = false
    @Published var isReady = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    
    private var isInitializing = false
    
    private init() {}
    
    /// Initialize the Parakeet ASR engine
    func initialize(language: String = "fr") async throws {
        if isInitializing {
            print("⚠️ TranscriptionManager: Already initializing, skipping...")
            return
        }
        
        isInitializing = true
        defer { isInitializing = false }
        
        isLoading = true
        statusMessage = L10n.isFrench ? "Initialisation..." : "Initializing..."
        progress = 0
        currentLanguage = language
        
        let targetModelURL = getModelDirectoryURL()
        print("📂 TranscriptionManager: Target model path is \(targetModelURL.path)")
        
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
                print("📂 TranscriptionManager: Model found at target path. Loading...")
                statusMessage = L10n.isFrench ? "Chargement des modèles..." : "Loading models..."
                progress = 0.45
                models = try await AsrModels.load(from: targetModelURL)
                progress = 0.75
            } else {
                print("📂 TranscriptionManager: Model NOT found. Initializing download...")
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
                
                print("📂 TranscriptionManager: Download complete. Migrating to SupraSonic folder...")
                statusMessage = L10n.isFrench ? "Organisation des fichiers..." : "Organizing files..."
                progress = 0.8
                // Immediately migrate to SupraSonic folder and CLEAN UP FluidAudio
                try migrateModelToSupraSonic()
                
                // RELOAD from the final destination to ensure we have correct paths
                let finalModelURL = getModelDirectoryURL()
                print("📂 TranscriptionManager: Reloading models from \(finalModelURL.path)...")
                models = try await AsrModels.load(from: finalModelURL)
            }
            
            print("⚙️ TranscriptionManager: Initializing ASR Manager (Compilation)...")
            statusMessage = L10n.isFrench ? "Optimisation des modèles (cela peut prendre une minute)..." : "Optimizing models (this may take a minute)..."
            // Start at 82% and let monitoring task nudge it
            if progress < 0.82 { progress = 0.82 }
            
            let asrManager = AsrManager(config: .default)
            try await asrManager.initialize(models: models)
            
            print("🔥🔥 TranscriptionManager: Pre-warming model...")
            statusMessage = L10n.isFrench ? "Finalisation..." : "Finalizing..."
            progress = 0.96
            
            // Pre-warm the model
            let dummySamples = [Float](repeating: 0, count: 1600)
            _ = try? await asrManager.transcribe(dummySamples)
            
            fluidAsr = asrManager
            isReady = true
            isLoading = false
            statusMessage = L10n.isFrench ? "Prêt" : "Ready"
            progress = 1.0
            print("✅ TranscriptionManager: Initialization complete")
            
            // Clean up old model versions to free disk space
            cleanupOldModels()
        } catch {
            print("❌ TranscriptionManager: Initialization failed: \(error.localizedDescription)")
            isLoading = false
            isReady = false
            statusMessage = "\(L10n.isFrench ? "Erreur" : "Error"): \(error.localizedDescription)"
            throw error
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
        print("📂 TranscriptionManager: Looking for target model: \(targetPath.lastPathComponent)")
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
                print("🧹 TranscriptionManager: Purging old model version: \(url.lastPathComponent)")
                try? fileManager.removeItem(at: url)
            }
        }
    }
    
    private func purgeLegacyDirectory() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacyDir = appSupport.appendingPathComponent("FluidAudio")
        
        if fileManager.fileExists(atPath: legacyDir.path) {
            print("🧹 TranscriptionManager: Purging legacy FluidAudio directory...")
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
            print("📂 Migration: Source directory not found (nothing downloaded?)")
            return
        }
        
        // Find any model directory in source
        let contents = try fileManager.contentsOfDirectory(at: sourceBase, includingPropertiesForKeys: nil)
        guard let modelDir = contents.first(where: { $0.hasDirectoryPath }) else {
            print("📂 Migration: No model directory found in source")
            return
        }
        
        let modelName = modelDir.lastPathComponent
        print("📂 Migration: Found model '\(modelName)'")
        
        let destModel = destBase.appendingPathComponent(modelName)
        
        if !fileManager.fileExists(atPath: destModel.path) {
            print("📂 Migration: Moving \(modelName) to SupraSonic...")
            
            // Create parent directories
            try fileManager.createDirectory(at: destBase, withIntermediateDirectories: true)
            
            // Move the whole model folder
            try fileManager.moveItem(at: modelDir, to: destModel)
            
            print("✅ Migration: Complete")
        } else {
            print("📂 Migration: Destination already exists. Skipping.")
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
        return result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

// MARK: - Errors

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
