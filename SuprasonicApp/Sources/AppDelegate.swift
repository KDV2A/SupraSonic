import Cocoa
import AVFoundation
import Carbon.HIToolbox
import SupraSonicCore

class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow?
    private var settingsWindow: SettingsWindow?
    
    // Rust Core State
    private var rustState: AppState?
    
    private var isRecording = false
    private var pushToTalkDown = false
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var toggleKeyDown = false
    
    // LLM Mode State
    private var isLLMMode = false
    private var llmOptionDown = false
    
    private var lastUIUpdate: CFTimeInterval = 0
    // Tracking for consecutive transcriptions
    private var lastTranscriptionTime: Date? = nil
    
    private var setupWindow: SetupWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Check if running from DMG (Anti-Translocation)
        let bundlePath = Bundle.main.bundleURL.path
        if bundlePath.contains("/Volumes/") && !bundlePath.contains("/Users/") {
            print("🚫 App: Running from DMG/Translocated. Blocking.")
            let alert = NSAlert()
            alert.messageText = L10n.isFrench ? "Installation requise" : "Installation Required"
            alert.informativeText = L10n.isFrench 
                ? "Merci de glisser l’application dans le dossier Applications avant de l’ouvrir."
                : "Please drag the application to the Applications folder before opening it."
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.isFrench ? "Quitter" : "Quit")
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }

        // 2. Check system compatibility
        if !checkCompatibility() {
            return
        }
        
        // 2. Create windows
        overlayWindow = OverlayWindow()
        settingsWindow = SettingsWindow()
        
        // Listen for hotkey settings changes
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeySettingsChanged), name: Constants.NotificationNames.hotkeySettingsChanged, object: nil)
        
        // Listen for model selection changes
        NotificationCenter.default.addObserver(self, selector: #selector(onModelSelectionChanged), name: Constants.NotificationNames.modelSelectionChanged, object: nil)
        
        // Listen for setup completion
        NotificationCenter.default.addObserver(self, selector: #selector(onSetupComplete), name: Constants.NotificationNames.setupComplete, object: nil)
        
        // Listen for system wake and audio changes
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioConfigChange), name: .AVAudioEngineConfigurationChange, object: nil)
        
        // 3. Check if setup is needed
        if shouldShowSetup() {
            // Show in Dock during setup
            NSApp.setActivationPolicy(.regular)
            showSetup()
        } else {
            setupStatusItem()
            proceedWithApp()
        }
    }
    
    private func shouldShowSetup() -> Bool {
        // 1. If setup was never completed, ALWAYS show it
        let setupCompleted = UserDefaults.standard.bool(forKey: Constants.Keys.setupCompleted)
        print("🚀 Onboarding debug: setupCompleted=\(setupCompleted)")
        
        if !setupCompleted {
            print("🚀 App: Onboarding never completed. Showing setup.")
            return true
        }
        
        // 2. Check system-level requirements
        let hasMic = PermissionsManager.shared.checkMicrophonePermission() == .granted
        let hasAccessibility = PermissionsManager.shared.checkAccessibilityPermission()
        let hasModel = ModelManager.shared.hasAnyModel()
        let isInApplications = Bundle.main.bundleURL.path.hasPrefix("/Applications")
        
        print("🚀 Onboarding debug: hasMic=\(hasMic), hasAccessibility=\(hasAccessibility), hasModel=\(hasModel), isInApplications=\(isInApplications)")
        
        // 3. If everything is OK, don't show setup
        if hasMic && hasAccessibility && hasModel && (isInApplications || !Bundle.main.bundleURL.path.contains(".dmg")) {
            print("🚀 App: All requirements met. Skipping setup.")
            return false
        }
        
        // 4. Force setup if critical pieces are missing, even if "completed" before
        if !hasMic { print("🚀 App: Missing Microphone Permission. Re-showing setup.") }
        if !hasAccessibility { print("🚀 App: Missing Accessibility Permission. Re-showing setup.") }
        if !hasModel { print("🚀 App: Missing ML Model. Re-showing setup.") }
        if !isInApplications && Bundle.main.bundleURL.path.contains(".dmg") { print("🚀 App: App running from DMG. Re-showing setup (Translocation check).") }
        
        return true
    }
    
    private func showSetup() {
        setupWindow = SetupWindow()
        setupWindow?.makeKeyAndOrderFront(nil)
        
        // Force activation and bring to front
        NSApp.activate(ignoringOtherApps: true)
        
        // Try to hide the Finder window (DMG window) that often covers the app
        let hideFinderScript = """
        tell application "Finder"
            set visible of every process whose name is "Finder" to false
        end tell
        """
        if let script = NSAppleScript(source: hideFinderScript) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
    
    @objc private func onSetupComplete() {
        print("✅ App: Setup complete signal received")
        
        // 1. Remove observer immediately to prevent any potential double-calls
        NotificationCenter.default.removeObserver(self, name: Constants.NotificationNames.setupComplete, object: nil)
        
        // 2. Mark as completed in UserDefaults
        UserDefaults.standard.set(true, forKey: Constants.Keys.setupCompleted)
        UserDefaults.standard.synchronize()
        
        // Use a single serial cleanup sequence on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("🚀 App: Transitioning from Setup to Accessory mode...")
            
            // 3. Clean Break: Hide window and disable EVERYTHING before nil'ing
            // NOTE: Using orderOut(nil) followed by setting to nil (letting ARC handle it)
            // is safer than calling .close() during an activation policy change. 
            // AppKit can sometimes trigger double-frees or use-after-free if .close()
            // is called while the system is still processing window animations or policy shifts.
            if let window = self.setupWindow {
                window.animationBehavior = .none
                window.delegate = nil
                window.contentView = nil
                window.orderOut(nil)
            }
            
            // 4. Important: Nil the reference FIRST to let ARC handle it 
            // instead of calling .close(). This ensures that even if AppKit tries 
            // to access the window pointer during the policy switch, it's either
            // clearly null or safely held by the system's autorelease pool.
            self.setupWindow = nil
            
            // 5. AppKit Lifecycle Safety:
            // Small delay (0.2s) to let current runloop cycle finish with the window object dead
            // but BEFORE we switch the app's activation policy. Switching policy via 
            // NSApp.setActivationPolicy(.accessory) is a heavy operation that resets 
            // certain AppKit internal states.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                
                print("🚀 App: Switching policy and initializing main app...")
                NSApp.setActivationPolicy(.accessory)
                
                self.setupStatusItem()
                self.proceedWithApp()
                
                // Final re-activation of the status item app
                NSApp.activate(ignoringOtherApps: true)
                print("✨ App: Seamless launch complete")
            }
        }
    }
    
    private func proceedWithApp() {
        // Initialize Rust Core
        let state = AppState()
        self.rustState = state
        print("🦀 Rust Core Initialized")
        
        // Set listener for raw audio data
        state.setListener(listener: RustAudioListener(delegate: self))
        
        // Initialize ML Engine (Parakeet v3 via FluidAudio)
        Task {
            do {
                try await TranscriptionManager.shared.initialize()
                print("✅ ML Engine (Parakeet v3) Initialized")
            } catch {
                print("❌ ML Engine Initialization Failed: \(error)")
            }
        }
    
        // Setup global hotkeys
        self.setupHotKeys()
        
        // Initialize LLM Engine if enabled
        if SettingsManager.shared.llmEnabled {
            Task {
                do {
                    try await LLMManager.shared.initialize()
                    print("✅ LLM Engine (LFM-2.5) Initialized")
                } catch {
                    print("❌ LLM Engine Initialization Failed: \(error)")
                }
            }
        }
        
        let llmSuffix = SettingsManager.shared.llmEnabled ? ", Right Option for LLM." : "."
        print("🎤 \(Constants.appName) ready! Hold Right Command to record\(llmSuffix)")
    }
    
    private func checkCompatibility() -> Bool {
        // Check macOS version (Minimum 14.0 Sonoma)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion < 14 {
            let alert = NSAlert()
            alert.messageText = L10n.isFrench ? "Version macOS non supportée" : "Unsupported macOS Version"
            alert.informativeText = L10n.isFrench 
                ? "\(Constants.appName) nécessite macOS 14.0 (Sonoma) ou plus récent pour fonctionner avec le moteur Parakeet."
                : "\(Constants.appName) requires macOS 14.0 (Sonoma) or newer to run with the Parakeet engine."
            alert.alertStyle = .critical
            alert.addButton(withTitle: L10n.isFrench ? "Quitter" : "Quit")
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return false
        }
        
        // Check architecture (Apple Silicon recommended/required for Neural Engine)
        #if arch(x86_64)
        let alert = NSAlert()
        alert.messageText = L10n.isFrench ? "Mac non compatible" : "Incompatible Mac"
        alert.informativeText = L10n.isFrench
            ? "\(Constants.appName) est optimisé pour les processeurs Apple Silicon (M1, M2, M3, M4). Les processeurs Intel ne sont pas supportés par le moteur de transcription actuel."
            : "\(Constants.appName) is optimized for Apple Silicon processors (M1, M2, M3, M4). Intel processors are not supported by the current transcription engine."
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.isFrench ? "Quitter" : "Quit")
        alert.runModal()
        NSApplication.shared.terminate(nil)
        return false
        #endif
        
        return true
    }
    
    @objc private func onModelSelectionChanged() {
        print("🔄 Settings changed, reinitializing...")
        initializeTranscription()
    }
    
    private func initializeTranscription() {
        Task { @MainActor in
            do {
                if TranscriptionManager.shared.isReady {
                    print("✅ Parakeet already initialized.")
                    return
                }

                let language = ModelManager.shared.selectedLanguage
                
                print("📦 Initializing Parakeet with language: \(language)")
                try await TranscriptionManager.shared.initialize(language: language)
                print("✅ Parakeet ready!")
            } catch {
                print("❌ Failed to initialize Parakeet: \(error)")
                // Show alert to user
                showTranscriptionError(error)
            }
        }
    }
    
    private func showTranscriptionError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Erreur de transcription"
            alert.informativeText = "Impossible d'initialiser le modèle de transcription: \(error.localizedDescription)\n\nLe modèle sera téléchargé automatiquement."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    @objc private func hotkeySettingsChanged() {
        // Re-setup hotkeys when settings change
        removeHotkeyMonitors()
        setupHotKeys()
    }
    
    private func removeHotkeyMonitors() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
    
    func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("✅ Microphone access granted")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    print("✅ Microphone access granted")
                } else {
                    print("❌ Microphone access denied")
                }
            }
        case .denied, .restricted:
            print("❌ Microphone access denied/restricted")
            showMicrophoneAlert()
        @unknown default:
            break
        }
    }
    
    func showMicrophoneAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Microphone Access Required"
            alert.informativeText = "\(Constants.appName) needs microphone access to transcribe your speech. Please enable it in System Settings > Privacy & Security > Microphone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Try multiple locations for the icon
            var icon: NSImage?
            
            // 1. Try main bundle Resources folder (primary location for bundled app)
            if let iconURL = Bundle.main.url(forResource: "suprasonic-icon-black", withExtension: "png") {
                icon = NSImage(contentsOf: iconURL)
            }
            
            // 2. Try in nested SPM resource bundle (for relocated bundles)
            if icon == nil {
                if let bundleURL = Bundle.main.url(forResource: "SupraSonicApp_SupraSonicApp", withExtension: "bundle"),
                   let resourceBundle = Bundle(url: bundleURL) {
                    if let iconURL = resourceBundle.url(forResource: "icon_32x32@2x", withExtension: "png") {
                        icon = NSImage(contentsOf: iconURL)
                    }
                }
            }
            
            if let icon = icon {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                // Fallback to system symbol
                button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: Constants.appName)
                button.image?.isTemplate = true
            }
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: Constants.appName, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Microphone submenu
        let micMenuItem = NSMenuItem(title: L10n.current.selectMicrophone, action: nil, keyEquivalent: "")
        micMenuItem.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
        let micSubmenu = NSMenu()
        micMenuItem.submenu = micSubmenu
        menu.addItem(micMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: L10n.current.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: L10n.current.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        
        // Update microphone menu
        updateMicrophoneMenu()
    }
    
    @objc func openSettings() {
        settingsWindow?.show()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private func updateMicrophoneMenu() {
        guard let menu = statusItem.menu,
              let micMenuItem = menu.items.first(where: { $0.title == L10n.current.selectMicrophone }),
              let micSubmenu = micMenuItem.submenu else { return }
        
        micSubmenu.removeAllItems()
        
        let devices = AudioDeviceManager.shared.getInputDevices()
        let selectedDevice = AudioDeviceManager.shared.getSelectedDevice()
        
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            item.state = device.uid == selectedDevice?.uid ? .on : .off
            micSubmenu.addItem(item)
        }
    }
    
    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        if let device = sender.representedObject as? AudioDeviceManager.AudioDevice {
            AudioDeviceManager.shared.setInputDevice(device)
            updateMicrophoneMenu()
        }
    }
    
    func setupHotKeys() {
        let settings = SettingsManager.shared
        let mainKeyCode = settings.pushToTalkKey
        let isMainModifier = isModifierKeyCode(mainKeyCode)
        
        // Monitor for Main Hotkey
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleMainHotkey(event: event, keyCode: mainKeyCode, isModifier: isMainModifier)
            self?.handleLLMHotkey(event: event)
        }
        
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleMainHotkey(event: event, keyCode: mainKeyCode, isModifier: isMainModifier)
            self?.handleLLMHotkey(event: event)
            return event
        }
        
        // Monitor for regular keys if the main hotkey is not a modifier
        if !isMainModifier {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleMainHotkey(event: event, keyCode: mainKeyCode, isModifier: false)
            }
            
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleMainHotkey(event: event, keyCode: mainKeyCode, isModifier: false)
                return event
            }
        }
    }
    
    private func handleMainHotkey(event: NSEvent, keyCode: UInt16, isModifier: Bool) {
        let settings = SettingsManager.shared
        let mode = settings.hotkeyMode
        let requiredModifiers = settings.pushToTalkModifiers
        
        if isModifier {
            // Handle modifier keys (like Right Command, Left Shift, etc.)
            let keyPressed = event.keyCode == keyCode && isModifierActive(event: event, keyCode: keyCode)
            let keyReleased = event.keyCode == keyCode && !isModifierActive(event: event, keyCode: keyCode)
            
            if mode == .pushToTalk {
                if keyPressed && !pushToTalkDown {
                    pushToTalkDown = true
                    startRecording()
                } else if keyReleased && pushToTalkDown {
                    pushToTalkDown = false
                    stopRecording()
                }
            } else { // Toggle Mode
                if keyPressed && !toggleKeyDown {
                    toggleKeyDown = true
                    toggleRecording()
                } else if keyReleased {
                    toggleKeyDown = false
                }
            }
        } else {
            // Handle regular keys with modifiers
            if event.keyCode == keyCode {
                // Check if modifiers match (stripping device-specific bits)
                let currentModifiers = event.modifierFlags.rawValue & 0x1F0000
                if currentModifiers == (requiredModifiers & 0x1F0000) {
                    if mode == .toggle {
                        toggleRecording()
                    } else {
                        // For PTT with regular keys, we treat it as toggle for now 
                        // as global monitors don't reliably give keyUp for regular keys
                        toggleRecording() 
                    }
                }
            }
        }
    }
    
    private func handleLLMHotkey(event: NSEvent) {
        guard SettingsManager.shared.llmEnabled else { return }
        
        let keyCode = Constants.KeyCodes.optionRight
        let keyPressed = event.keyCode == keyCode && isModifierActive(event: event, keyCode: keyCode)
        let keyReleased = event.keyCode == keyCode && !isModifierActive(event: event, keyCode: keyCode)
        
        if keyPressed && !llmOptionDown {
            llmOptionDown = true
            isLLMMode = true
            startRecording()
        } else if keyReleased && llmOptionDown {
            llmOptionDown = false
            stopRecording()
            // isLLMMode will be reset in handleAudioBuffer after processing
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        return Constants.KeyCodes.modifiers.contains(keyCode)
    }
    
    private func isModifierActive(event: NSEvent, keyCode: UInt16) -> Bool {
        switch keyCode {
        case Constants.KeyCodes.commandRight: return (event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK)) != 0
        case Constants.KeyCodes.commandLeft: return (event.modifierFlags.rawValue & UInt(NX_DEVICELCMDKEYMASK)) != 0
        case Constants.KeyCodes.shiftLeft: return (event.modifierFlags.rawValue & UInt(NX_DEVICELSHIFTKEYMASK)) != 0
        case Constants.KeyCodes.shiftRight: return (event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK)) != 0
        case Constants.KeyCodes.optionLeft: return (event.modifierFlags.rawValue & UInt(NX_DEVICELALTKEYMASK)) != 0
        case Constants.KeyCodes.optionRight: return (event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK)) != 0
        case Constants.KeyCodes.controlLeft: return (event.modifierFlags.rawValue & UInt(NX_DEVICELCTLKEYMASK)) != 0
        case Constants.KeyCodes.controlRight: return (event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK)) != 0
        default: return false
        }
    }
    
    @objc private func handleWake() {
        print("☀️ System: Wake detected.")
        // restartAudioEngine() // Legacy disabled
    }
    
    @objc private func handleAudioConfigChange() {
        print("🔄 Audio: Configuration change detected.")
        // restartAudioEngine() // Legacy disabled
    }
    
    // private func restartAudioEngine() { ... }
    
    func setupAudioEngine() {
        // Disabled for Rust Migration
        print("⚠️ Legacy Audio Engine setup skipped.")
    }
    
    // private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) { ... }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Rust Core Start
        if let state = rustState {
            do {
                try state.startRecording()
                print("🦀 Rust: Start Capture")
            } catch {
                print("❌ Rust Start Failed: \(error)")
            }
        }
        
        isRecording = true
        
        DispatchQueue.main.async {
            self.overlayWindow?.show()
        }
        
        print("🎙️ Recording started...")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Rust Core Stop
        if let state = rustState {
            do {
                try state.stopRecording()
                print("🦀 Rust: Stop Capture")
            } catch {
                 print("❌ Rust Stop Failed: \(error)")
            }
        }
        
        isRecording = false
        
        DispatchQueue.main.async {
            self.overlayWindow?.hide()
        }
        
        print("⏹️ Recording stopped.")
    }
    
    func handleTranscriptionResult(_ text: String) {
        let isConsecutive = lastTranscriptionTime != nil && Date().timeIntervalSince(lastTranscriptionTime!) < Constants.consecutiveTranscriptionThreshold
        lastTranscriptionTime = Date()
        
        KeystrokeManager.shared.insertText(text, consecutive: isConsecutive)
    }
}

// MARK: - Rust Integration Helpers

protocol RustAudioDelegate: AnyObject {
    func handleAudioBuffer(_ audioData: [Float])
    func handleAudioLevel(_ level: Float)
}

class RustAudioListener: TranscriptionListener {
    weak var delegate: RustAudioDelegate?
    
    init(delegate: RustAudioDelegate) {
        self.delegate = delegate
    }
    
    func onAudioData(audioData: [Float]) {
        print("🎙️ Rust Audio Captured: \(audioData.count) samples")
        self.delegate?.handleAudioBuffer(audioData)
    }
    
    func onLevelChanged(level: Float) {
        self.delegate?.handleAudioLevel(level)
    }
}

extension AppDelegate: RustAudioDelegate {
    func handleAudioBuffer(_ audioData: [Float]) {
        Task {
            do {
                print("🧠 App: Starting Parakeet v3 inference...")
                let text = try await TranscriptionManager.shared.transcribe(audioSamples: audioData)
                
                print("📝 Parakeet Result: \(text)")
                if !text.isEmpty {
                    var finalOutput = text
                    
                    if self.isLLMMode {
                        print("🤖 App: Routing to LLM for processing...")
                        do {
                            finalOutput = try await LLMManager.shared.generateResponse(prompt: text)
                            print("✨ LLM Result: \(finalOutput)")
                        } catch {
                            print("❌ LLM processing failed: \(error)")
                            // Fallback to original text if LLM fails
                        }
                        self.isLLMMode = false
                    }
                    
                    DispatchQueue.main.async { [weak self] in
                        SettingsManager.shared.addToHistory(finalOutput)
                        self?.handleTranscriptionResult(finalOutput)
                    }
                }
            } catch {
                print("❌ Transcription failed: \(error)")
            }
        }
    }
    
    func handleAudioLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.overlayWindow?.updateLevel(level)
        }
    }
}

