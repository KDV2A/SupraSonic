import Cocoa

struct Constants {
    // MARK: - Branding
    static let appName = "SupraSonic"
    static let brandBlue = NSColor(red: 0, green: 0.9, blue: 1.0, alpha: 1.0)
    
    // MARK: - Audio
    static let targetSampleRate: Double = 16000
    static let maxBufferSamples = Int(16000 * 60) // 60 seconds
    static let modelSizeMB: Double = 600.0
    static let targetModelVersion = "v3" // Current Parakeet version
    static let targetModelName = "parakeet-tdt-0.6b-v3-coreml"
    
    // MARK: - LLM
    static let llmModelName = "alexgusevski/Ministral-3-3B-Instruct-2512-q4-mlx"
    static let llmMaxTokens = 512
    static let llmTemperature: Float = 0.7
    static let defaultAISkillPrompt = "Tu es un traducteur Français-Anglais professionnel, traduis l’input sans commentaires ni formatage. Input:"
    
    // Cloud Model Names (for display and API calls)
    static let geminiModelName = "gemini-1.5-flash"
    static let openaiModelName = "gpt-4o-mini"
    static let anthropicModelName = "claude-3-5-haiku-latest"
    
    // MARK: - UI
    static let uiUpdateFPS: Double = 30.0
    static let uiUpdateInterval: TimeInterval = 1.0 / uiUpdateFPS
    static let consecutiveTranscriptionThreshold: TimeInterval = 30.0
    
    // MARK: - Hotkey Scan Codes (Carbon)
    struct KeyCodes {
        static let escape: UInt16 = 0x35
        static let v: UInt16 = 0x09
        
        static let commandRight: UInt16 = 0x36
        static let commandLeft: UInt16 = 0x37
        static let shiftLeft: UInt16 = 0x38
        static let shiftRight: UInt16 = 0x3C
        static let optionLeft: UInt16 = 0x3A
        static let optionRight: UInt16 = 0x3D
        static let controlLeft: UInt16 = 0x3B
        static let controlRight: UInt16 = 0x3E
        
        static let modifiers: [UInt16] = [
            commandRight, commandLeft, shiftLeft, shiftRight,
            optionLeft, optionRight, controlLeft, controlRight
        ]
    }
    
    struct NotificationNames {
        static let setupComplete = Notification.Name("SetupComplete")
        static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
        static let modelSelectionChanged = Notification.Name("modelSelectionChanged")
        static let historyEntryAdded = Notification.Name("historyEntryAdded")
        static let microphoneChanged = Notification.Name("microphoneChanged")
    }
    
    struct Keys {
        static let setupCompleted = "SupraSonicSetupCompleted"
        static let selectedMicrophoneUID = "selectedMicrophoneUID"
        static let appleEventsRequested = "AppleEventsPermissionRequested"
        
        static let pushToTalkKey = "pushToTalkKey"
        static let pushToTalkModifiers = "pushToTalkModifiers"
        static let pushToTalkKeyString = "pushToTalkKeyString"
        static let hotkeyMode = "hotkeyMode"
        static let historyEnabled = "historyEnabled"
        static let launchOnLogin = "launchOnLogin"
        static let transcriptionHistory = "transcriptionHistory"
        static let aiSkills = "aiSkills"
        static let muteSystemSound = "muteSystemSound"
        static let llmProvider = "llmProvider"
        static let geminiApiKey = "geminiApiKey"
        static let openaiApiKey = "openaiApiKey"
        static let anthropicApiKey = "anthropicApiKey"
        static let vocabularyMapping = "vocabularyMapping"
    }
}
