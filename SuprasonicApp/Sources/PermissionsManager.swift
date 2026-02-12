import Cocoa
import AVFoundation
import ApplicationServices

class PermissionsManager {
    static let shared = PermissionsManager()
    
    private init() {}
    
    // MARK: - Permission Status
    
    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
    }
    
    // MARK: - Microphone Permission
    
    func checkMicrophonePermission() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    // MARK: - Accessibility Permission (for simulating keystrokes)
    
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Check All Permissions
    
    func checkAllPermissions() -> (microphone: PermissionStatus, accessibility: Bool) {
        return (checkMicrophonePermission(), checkAccessibilityPermission())
    }
    
    // MARK: - Show Setup Guide
    
    private let setupCompletedKey = "SupraSonicSetupCompleted"
    
    func showSetupGuideIfNeeded(completion: @escaping () -> Void) {
        let micStatus = checkMicrophonePermission()
        
        // Step 1: Request microphone if needed
        if micStatus == .notDetermined {
            requestMicrophonePermission { [weak self] granted in
                if granted {
                    self?.checkAndRequestAccessibility(completion: completion)
                } else {
                    completion()
                }
            }
            return
        }
        
        // Step 2: Check accessibility
        checkAndRequestAccessibility(completion: completion)
    }
    
    private func checkAndRequestAccessibility(completion: @escaping () -> Void) {
        if !checkAccessibilityPermission() {
            requestAccessibilityPermission()
        }
        completion()
    }
    
    // MARK: - Open System Settings
    
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Show Permission Error
    
    func showAccessibilityRequiredAlert() {
        let l = L10n.current
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = l.accessibilityRequiredTitle
            alert.informativeText = l.accessibilityRequiredMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: l.setupOpenAccessibilitySettings)
            alert.addButton(withTitle: l.cancel)
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.openAccessibilitySettings()
            }
        }
    }
    
    // MARK: - Advanced Repair (Pro Logic)
    
    /// Resets the accessibility permissions for the app using tccutil.
    /// This is used to fix "stale" TCC states where macOS doesn't recognize the permission change.
    func resetAccessibility() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        debugLog("🛠️ Permissions: Resetting TCC for \(bundleID)...")
        
        // Ensure onboarding reappears on relaunch
        UserDefaults.standard.set(false, forKey: "SupraSonicSetupCompleted")
        UserDefaults.standard.synchronize()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        
        try? process.run()
        process.waitUntilExit()
    }
    
    /// Relaunches the application. Required after a TCC reset for changes to take effect reliably.
    /// This uses a decoupled process (open -n) to ensure a fresh instance starts even as the current one terminates.
    func relaunchApp() {
        let appURL = Bundle.main.bundleURL
        debugLog("🚀 Permissions: Relaunching from \(appURL.path)...")
        
        // Spawn a decoupled 'open' command to launch a new instance
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appURL.path]
        
        do {
            try process.run()
            // Give it a tiny moment to start spawning before we die
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
        } catch {
            debugLog("❌ Permissions: Failed to relaunch: \(error)")
            // Fallback: just quit and hope user relanches
            NSApp.terminate(nil)
        }
    }
}

