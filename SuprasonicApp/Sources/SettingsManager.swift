import Foundation
import ServiceManagement

class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    enum HotkeyMode: Int, Codable {
        case pushToTalk = 0
        case toggle = 1
    }
    
    enum LLMProvider: String, Codable, CaseIterable {
        case none = "none"
        case local = "local"
        case google = "google"
        case openai = "openai"
        case anthropic = "anthropic"
        
        var displayName: String {
            switch self {
            case .none: return L10n.isFrench ? "Aucun" : "None"
            case .local: return "SupraSonic Local (Ministral-3B)"
            case .google: return "Google (Gemini)"
            case .openai: return "OpenAI (GPT-4o)"
            case .anthropic: return "Anthropic (Claude)"
            }
        }
    }
    
    // MARK: - Main Hotkey (default: Right Command)
    
    var hotkeyMode: HotkeyMode {
        get {
            let value = defaults.integer(forKey: Constants.Keys.hotkeyMode)
            // Default to .pushToTalk (0)
            if defaults.object(forKey: Constants.Keys.hotkeyMode) == nil { return .pushToTalk }
            return HotkeyMode(rawValue: value) ?? .pushToTalk
        }
        set { defaults.set(newValue.rawValue, forKey: Constants.Keys.hotkeyMode) }
    }
    
    var pushToTalkKey: UInt16 {
        get {
            let value = defaults.integer(forKey: Constants.Keys.pushToTalkKey)
            return value == 0 ? 0x36 : UInt16(value)  // 0x36 = Right Command
        }
        set { defaults.set(Int(newValue), forKey: Constants.Keys.pushToTalkKey) }
    }
    
    var pushToTalkKeyString: String {
        get {
            let value = defaults.string(forKey: Constants.Keys.pushToTalkKeyString)
            if value == nil && pushToTalkKey == 0x36 {
                return "⌘ " + (L10n.isFrench ? "Droite" : "Right")
            }
            return value ?? ""
        }
        set { defaults.set(newValue, forKey: Constants.Keys.pushToTalkKeyString) }
    }
    
    var pushToTalkModifiers: UInt {
        get {
            // If the key is specifically set to the default (Right Command), we default to Command modifier
            if defaults.object(forKey: Constants.Keys.pushToTalkModifiers) == nil {
                return (pushToTalkKey == 0x36) ? UInt(1 << 20) : 0
            }
            return UInt(defaults.integer(forKey: Constants.Keys.pushToTalkModifiers))
        }
        set { defaults.set(Int(newValue), forKey: Constants.Keys.pushToTalkModifiers) }
    }
    
    var pushToTalkIsRightCommand: Bool {
        get { pushToTalkKey == 0x36 }
    }
    
    // MARK: - History
    
    var historyEnabled: Bool {
        get { defaults.bool(forKey: Constants.Keys.historyEnabled) }
        set { defaults.set(newValue, forKey: Constants.Keys.historyEnabled) }
    }
    
    var aiSkills: [AISkill] {
        get {
            if let data = defaults.data(forKey: Constants.Keys.aiSkills),
               let skills = try? JSONDecoder().decode([AISkill].self, from: data) {
                return skills
            }
            // Default skills if none exist
            let defaults = [
                AISkill(name: L10n.isFrench ? "Traduction" : "Translation",
                        trigger: L10n.isFrench ? "traduction" : "translation",
                        prompt: Constants.defaultAISkillPrompt,
                        color: "blue")
            ]
            return defaults
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Constants.Keys.aiSkills)
            }
        }
    }
    
    // Legacy support (will be removed in future)
    var aiAssistantPrompt: String {
        get { aiSkills.first?.prompt ?? Constants.defaultAISkillPrompt }
    }
    
    var llmEnabled: Bool {
        get { llmProvider != .none }
        set { 
            if newValue {
                if llmProvider == .none {
                    llmProvider = .local // Default to local if enabling
                }
            } else {
                llmProvider = .none
            }
        }
    }
    
    var llmProvider: LLMProvider {
        get {
            let value = defaults.string(forKey: Constants.Keys.llmProvider) ?? LLMProvider.none.rawValue
            return LLMProvider(rawValue: value) ?? .none
        }
        set { defaults.set(newValue.rawValue, forKey: Constants.Keys.llmProvider) }
    }
    
    var geminiApiKey: String {
        get { defaults.string(forKey: Constants.Keys.geminiApiKey) ?? "" }
        set { defaults.set(newValue, forKey: Constants.Keys.geminiApiKey) }
    }
    
    var openaiApiKey: String {
        get { defaults.string(forKey: Constants.Keys.openaiApiKey) ?? "" }
        set { defaults.set(newValue, forKey: Constants.Keys.openaiApiKey) }
    }
    
    var anthropicApiKey: String {
        get { defaults.string(forKey: Constants.Keys.anthropicApiKey) ?? "" }
        set { defaults.set(newValue, forKey: Constants.Keys.anthropicApiKey) }
    }
    
    var vocabularyMapping: [String: String] {
        get { defaults.dictionary(forKey: Constants.Keys.vocabularyMapping) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Constants.Keys.vocabularyMapping) }
    }
    
    var transcriptionHistory: [TranscriptionEntry] {
        get {
            guard let data = defaults.data(forKey: Constants.Keys.transcriptionHistory),
                  let entries = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) else {
                return []
            }
            return entries
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Constants.Keys.transcriptionHistory)
            }
        }
    }
    
    var muteSystemSoundDuringRecording: Bool {
        get { defaults.bool(forKey: Constants.Keys.muteSystemSound) }
        set { defaults.set(newValue, forKey: Constants.Keys.muteSystemSound) }
    }
    
    func addToHistory(_ text: String) {
        guard historyEnabled, !text.isEmpty else { return }
        let entry = TranscriptionEntry(text: text, date: Date())
        var history = transcriptionHistory
        history.insert(entry, at: 0)
        // Keep last 100 entries
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        transcriptionHistory = history
        
        // Notify observers for real-time update
        NotificationCenter.default.post(name: Constants.NotificationNames.historyEntryAdded, object: entry)
    }
    
    func clearHistory() {
        transcriptionHistory = []
    }
    
    // MARK: - Launch on Login
    
    var launchOnLogin: Bool {
        get { defaults.bool(forKey: Constants.Keys.launchOnLogin) }
        set {
            defaults.set(newValue, forKey: Constants.Keys.launchOnLogin)
            updateLaunchOnLogin(newValue)
        }
    }
    
    private func updateLaunchOnLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("❌ Failed to update launch on login: \(error)")
            }
        }
    }
    
    // MARK: - Reset to Defaults
    
    func resetToDefaults() {
        defaults.removeObject(forKey: Constants.Keys.pushToTalkKey)
        defaults.removeObject(forKey: Constants.Keys.pushToTalkModifiers)
        defaults.removeObject(forKey: Constants.Keys.pushToTalkKeyString)
        defaults.removeObject(forKey: Constants.Keys.hotkeyMode)
        defaults.removeObject(forKey: Constants.Keys.historyEnabled)
        defaults.removeObject(forKey: Constants.Keys.launchOnLogin)
        defaults.removeObject(forKey: Constants.Keys.transcriptionHistory)
    }
}

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
    
    init(text: String, date: Date) {
        self.id = UUID()
        self.text = text
        self.date = date
    }
}

struct AISkill: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var trigger: String
    var prompt: String
    var color: String
    var isExpanded: Bool = false
    
    init(name: String, trigger: String, prompt: String, color: String = "blue") {
        self.id = UUID()
        self.name = name
        self.trigger = trigger
        self.prompt = prompt
        self.color = color
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, trigger, prompt, color
    }
}
