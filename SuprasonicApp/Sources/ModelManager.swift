import Foundation

/// Simplified ModelManager for WhisperKit
/// WhisperKit handles model downloads automatically, this just manages preferences
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
        
        // Check if any subdirectory exists (which would be a model)
        if let contents = try? FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) {
            return contents.contains { $0.hasDirectoryPath }
        }
        
        return false
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let modelSelectionChanged = Notification.Name("modelSelectionChanged")
}
