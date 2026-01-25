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
    
    private let setupCompletedKey = "SuprasonicSetupCompleted"
    
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
}
