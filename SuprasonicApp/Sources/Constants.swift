import Cocoa
import os.log

/// Lightweight debug-only logger. Stripped from release builds.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

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
    static let geminiModelName = "Gemini 2.5 Flash"
    static let openaiModelName = "GPT-5.2"
    static let anthropicModelName = "Claude Opus 4.6"
    
    // Available Gemini Models (curated from Google AI Studio, Feb 2026)
    struct GeminiModel {
        let id: String        // API model ID (e.g. "gemini-2.5-flash")
        let displayName: String
        
        static let allModels: [GeminiModel] = [
            GeminiModel(id: "gemini-3-flash", displayName: "Gemini 3 Flash"),
            GeminiModel(id: "gemini-3-pro-preview", displayName: "Gemini 3 Pro (Preview)"),
            GeminiModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
            GeminiModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
            GeminiModel(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash-Lite"),
            GeminiModel(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash"),
        ]
        
        static let defaultModelId = "gemini-2.5-flash"
    }
    
    // Available OpenAI Models (Feb 2026)
    struct OpenAIModel {
        let id: String
        let displayName: String
        
        static let allModels: [OpenAIModel] = [
            OpenAIModel(id: "gpt-5.2", displayName: "GPT-5.2"),
            OpenAIModel(id: "gpt-5.2-mini", displayName: "GPT-5.2 Mini"),
            OpenAIModel(id: "gpt-5.2-nano", displayName: "GPT-5.2 Nano"),
            OpenAIModel(id: "o3", displayName: "o3"),
            OpenAIModel(id: "o3-mini", displayName: "o3-mini"),
        ]
        
        static let defaultModelId = "gpt-5.2"
    }
    
    // Available Anthropic Models (Feb 2026)
    struct AnthropicModel {
        let id: String
        let displayName: String
        
        static let allModels: [AnthropicModel] = [
            AnthropicModel(id: "claude-opus-4-6", displayName: "Claude Opus 4.6"),
            AnthropicModel(id: "claude-opus-4-5", displayName: "Claude Opus 4.5"),
            AnthropicModel(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5"),
            AnthropicModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
        ]
        
        static let defaultModelId = "claude-opus-4-6"
    }
    
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
        static let meetingTranscriptUpdated = Notification.Name("meetingTranscriptUpdated")
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
        static let showIconInDock = "showIconInDock"
        static let geminiModelId = "geminiModelId"
        static let openaiModelId = "openaiModelId"
        static let anthropicModelId = "anthropicModelId"
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexSanitized.hasPrefix("#") { hexSanitized.remove(at: hexSanitized.startIndex) }
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        self.init(red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                  green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                  blue: CGFloat(rgb & 0x0000FF) / 255.0,
                  alpha: 1.0)
    }
}
