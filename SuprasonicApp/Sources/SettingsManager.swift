import Foundation
import ServiceManagement

class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    enum HotkeyMode: Int, Codable {
        case pushToTalk = 0
        case toggle = 1
    }
    
    // MARK: - Main Hotkey (default: Right Command)
    
    var hotkeyMode: HotkeyMode {
        get {
            let value = defaults.integer(forKey: Constants.Keys.hotkeyMode)
            // Default to .toggle (1) instead of .pushToTalk (0)
            if defaults.object(forKey: Constants.Keys.hotkeyMode) == nil { return .toggle }
            return HotkeyMode(rawValue: value) ?? .toggle
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
    
    var llmEnabled: Bool {
        get { defaults.bool(forKey: Constants.Keys.llmEnabled) }
        set { defaults.set(newValue, forKey: Constants.Keys.llmEnabled) }
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
