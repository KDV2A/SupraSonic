import Cocoa
import ApplicationServices

class KeystrokeManager {
    static let shared = KeystrokeManager()
    
    private init() {}
    
    /// Inserts the given text into the frontmost application.
    /// This uses a combination of clipboard manipulation and simulated keystrokes.
    func insertText(_ text: String, consecutive: Bool = false) {
        var textToInsert = text
        
        // Add a leading space for consecutive transcriptions
        if consecutive {
            textToInsert = " " + textToInsert
        }
        
        // 1. Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToInsert, forType: .string)
        
        print("📋 KeystrokeManager: Text copied to clipboard")
        
        // 2. Try to paste with a brief delay (100ms) to ensure clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            var pasteSucceeded = false
            let hasRequestedAppleEvents = UserDefaults.standard.bool(forKey: "AppleEventsPermissionRequested")
            
            if !hasRequestedAppleEvents {
                pasteSucceeded = self.performPasteViaAppleScript()
                if pasteSucceeded {
                    UserDefaults.standard.set(true, forKey: "AppleEventsPermissionRequested")
                }
            }
            
            // 3. Fallback to CGEvent if AppleScript skipped or failed
            if !pasteSucceeded {
                self.performPasteViaCGEvent()
            }
        }
    }
    
    private func performPasteViaAppleScript() -> Bool {
        print("📋 KeystrokeManager: Attempting paste via AppleScript")
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if error == nil {
                print("✅ KeystrokeManager: AppleScript paste success")
                return true
            } else {
                print("⚠️ KeystrokeManager: AppleScript paste failed: \(String(describing: error))")
                return false
            }
        }
        return false
    }
    
    private func performPasteViaCGEvent() {
        print("🎯 KeystrokeManager: Attempting paste via CGEvent (Accessibility)")
        
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdKey: UInt16 = 0x37 // Left Command
        let vKey: UInt16 = 0x09   // 'v'
        
        guard let pbtDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true),
              let pbtUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            print("❌ KeystrokeManager: Failed to create CGEvents")
            return
        }
        
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        
        // Full sequence: Cmd Down -> V Down -> V Up -> Cmd Up
        pbtDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        pbtUp.post(tap: .cghidEventTap)
    }
}
