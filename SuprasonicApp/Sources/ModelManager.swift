import Foundation

/// Simplified ModelManager for FluidAudio/Parakeet
/// Managed preferences for the local transcription engine.
class ModelManager {
    static let shared = ModelManager()
    
    private let defaults = UserDefaults.standard
    private let languageKey = "transcriptionLanguage"
    
    // MARK: - Language
    
    var selectedLanguage: String {
        get {
            return defaults.string(forKey: languageKey) ?? "fr"
        }
        set {
            defaults.set(newValue, forKey: languageKey)
        }
    }
    
    func hasAnyModel() -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("SupraSonic/models/huggingface.co/mlx-community")
        
        let targetModelDir = baseDir.appendingPathComponent(Constants.targetModelName)
        return FileManager.default.fileExists(atPath: targetModelDir.path)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let modelSelectionChanged = Notification.Name("modelSelectionChanged")
}
