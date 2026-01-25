import Foundation
import ServiceManagement

class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let pushToTalkKeyKey = "pushToTalkKey"
    private let pushToTalkModifiersKey = "pushToTalkModifiers"
    private let pushToTalkKeyStringKey = "pushToTalkKeyString"
    private let hotkeyModeKey = "hotkeyMode"
    private let toggleRecordKeyKey = "toggleRecordKey"
    private let toggleRecordModifiersKey = "toggleRecordModifiers"
    private let historyEnabledKey = "historyEnabled"
    private let launchOnLoginKey = "launchOnLogin"
    private let transcriptionHistoryKey = "transcriptionHistory"
    
    enum HotkeyMode: Int, Codable {
        case pushToTalk = 0
        case toggle = 1
    }
    
    // MARK: - Main Hotkey (default: Right Command)
    
    var hotkeyMode: HotkeyMode {
        get {
            let value = defaults.integer(forKey: hotkeyModeKey)
            // Default to .toggle (1) instead of .pushToTalk (0)
            if defaults.object(forKey: hotkeyModeKey) == nil { return .toggle }
            return HotkeyMode(rawValue: value) ?? .toggle
        }
        set { defaults.set(newValue.rawValue, forKey: hotkeyModeKey) }
    }
    
    var pushToTalkKey: UInt16 {
        get {
            let value = defaults.integer(forKey: pushToTalkKeyKey)
            return value == 0 ? 0x36 : UInt16(value)  // 0x36 = Right Command
        }
        set { defaults.set(Int(newValue), forKey: pushToTalkKeyKey) }
    }
    
    var pushToTalkKeyString: String {
        get {
            let value = defaults.string(forKey: pushToTalkKeyStringKey)
            if value == nil && pushToTalkKey == 0x36 {
                return "⌘ " + (L10n.isFrench ? "Droite" : "Right")
            }
            return value ?? ""
        }
        set { defaults.set(newValue, forKey: pushToTalkKeyStringKey) }
    }
    
    var pushToTalkModifiers: UInt {
        get {
            // If the key is specifically set to the default (Right Command), we default to Command modifier
            if defaults.object(forKey: pushToTalkModifiersKey) == nil {
                return (pushToTalkKey == 0x36) ? UInt(1 << 20) : 0
            }
            return UInt(defaults.integer(forKey: pushToTalkModifiersKey))
        }
        set { defaults.set(Int(newValue), forKey: pushToTalkModifiersKey) }
    }
    
    var pushToTalkIsRightCommand: Bool {
        get { pushToTalkKey == 0x36 }
    }
    
    // MARK: - Legacy Toggle Record Hotkey (kept for migration safety, but no longer used in UI)
    
    // MARK: - History
    
    var historyEnabled: Bool {
        get { defaults.bool(forKey: historyEnabledKey) }
        set { defaults.set(newValue, forKey: historyEnabledKey) }
    }
    
    var transcriptionHistory: [TranscriptionEntry] {
        get {
            guard let data = defaults.data(forKey: transcriptionHistoryKey),
                  let entries = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) else {
                return []
            }
            return entries
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: transcriptionHistoryKey)
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
        NotificationCenter.default.post(name: .historyEntryAdded, object: entry)
    }
    
    func clearHistory() {
        transcriptionHistory = []
    }
    
    // MARK: - Launch on Login
    
    var launchOnLogin: Bool {
        get { defaults.bool(forKey: launchOnLoginKey) }
        set {
            defaults.set(newValue, forKey: launchOnLoginKey)
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
        defaults.removeObject(forKey: pushToTalkKeyKey)
        defaults.removeObject(forKey: pushToTalkModifiersKey)
        defaults.removeObject(forKey: pushToTalkKeyStringKey)
        defaults.removeObject(forKey: toggleRecordKeyKey)
        defaults.removeObject(forKey: toggleRecordModifiersKey)
        defaults.removeObject(forKey: historyEnabledKey)
        defaults.removeObject(forKey: launchOnLoginKey)
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
