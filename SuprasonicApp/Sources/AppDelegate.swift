import Cocoa
import AVFoundation
import Carbon.HIToolbox
import SupraSonicCore

@MainActor
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
    
    // AI Skills State
    private var isLLMMode = false
    private var capturedSelectedText: String? = nil
    private var savedVolumeLevel: Int? = nil
    
    private var lastUIUpdate: CFTimeInterval = 0
    // Tracking for consecutive transcriptions
    private var lastTranscriptionTime: Date? = nil
    
    private var setupWindow: SetupWindow?
    private var meetingDetailWindow: MeetingDetailWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("🎬 applicationDidFinishLaunching")
        NSApp.activate(ignoringOtherApps: true)
        
        // 1. Check if running from DMG (Anti-Translocation)
        let bundlePath = Bundle.main.bundleURL.path
        if bundlePath.contains("/Volumes/") && !bundlePath.contains("/Users/") {
            debugLog("🚫 App: Running from DMG/Translocated. Blocking.")
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
        
        // Setup minimal main menu for shortcuts (Copy/Paste)
        setupMainMenu()
        
        // Setup paste error callback - show recovery modal after multiple failures
        KeystrokeManager.shared.onPasteError = { [weak self] in
            let reason = L10n.isFrench
                ? "Le collage de texte ne fonctionne pas. Les permissions d'accessibilité peuvent être corrompues."
                : "Text pasting is not working. Accessibility permissions may be corrupted."
            self?.showRecoveryModal(reason: reason)
        }
        
        // Listen for model selection changes
        NotificationCenter.default.addObserver(self, selector: #selector(onModelSelectionChanged), name: Constants.NotificationNames.modelSelectionChanged, object: nil)
        
        // Listen for setup completion
        NotificationCenter.default.addObserver(self, selector: #selector(onSetupComplete), name: Constants.NotificationNames.setupComplete, object: nil)
        
        // Listen for system wake and audio changes
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioConfigChange), name: .AVAudioEngineConfigurationChange, object: nil)
        
        // Listen for Meeting Live Transcripts
        NotificationCenter.default.addObserver(self, selector: #selector(onMeetingTranscriptUpdated(_:)), name: Constants.NotificationNames.meetingTranscriptUpdated, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeySettingsChanged), name: Constants.NotificationNames.hotkeySettingsChanged, object: nil)
        
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
        debugLog("🚀 Onboarding debug: setupCompleted=\(setupCompleted)")
        
        if !setupCompleted {
            debugLog("🚀 App: Onboarding never completed. Showing setup.")
            return true
        }
        
        // 2. Reinstall detection: If setup was "completed" but models are missing,
        //    the user likely trashed the app and reinstalled. Reset and show onboarding.
        let hasModel = ModelManager.shared.hasAnyModel()
        if !hasModel {
            debugLog("🚀 App: Models missing (likely reinstall after uninstall). Resetting setup.")
            UserDefaults.standard.set(false, forKey: Constants.Keys.setupCompleted)
            // Clean up stale accessibility permissions from previous install
            removeAccessibilityPermissions()
            return true
        }
        
        return false
    }
    
    @MainActor
    private func showSetup() {
        setupWindow = SetupWindow()
        setupWindow?.makeKeyAndOrderFront(nil)
        
    }
    
    @MainActor
    @objc private func onSetupComplete() {
        debugLog("✅ App: Setup complete signal received")
        
        // 1. Remove observer immediately
        NotificationCenter.default.removeObserver(self, name: Constants.NotificationNames.setupComplete, object: nil)
        
        // 2. Mark as completed in UserDefaults
        UserDefaults.standard.set(true, forKey: Constants.Keys.setupCompleted)
        UserDefaults.standard.synchronize()
        
        // 3. Hide the setup window
        if let window = setupWindow {
            window.orderOut(nil)
        }
        
        // 4. Delayed transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            debugLog("🚀 App: Starting transition sequence...")
            self.setupWindow = nil
            
            if SettingsManager.shared.showInDock {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
            
            self.setupStatusItem()
            
            self.proceedWithApp()
            
            NSApp.activate(ignoringOtherApps: true)
            self.openSettings()
        }
    }
    
    private func proceedWithApp() {
        debugLog("🚀 App: proceedWithApp started")
        
        // Initialize Rust Core
            // Start Rust Core
            // Initialize AppState
            debugLog("🚀 App: Initializing AppState...")
            // Provide path for persistent speaker registry
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let speakerPath = appSupport.appendingPathComponent("SupraSonic/speakers.json").path
            
            let state = AppState()
            self.rustState = state
            debugLog("🦀 Rust Core Initialized (Speakers: \(speakerPath))")
            
            // Set listener for raw audio data
            state.setListener(listener: RustAudioListener(delegate: self))
            
            // Initialize ML Engine (Parakeet v3 via FluidAudio)
            Task {
                do {
                    debugLog("🚀 App: TranscriptionManager.shared.initialize()...")
                    try await TranscriptionManager.shared.initialize()
                    debugLog("✅ ML Engine (Parakeet v3) Initialized")
                    
                    // Initialize Meeting Manager
                    debugLog("🚀 App: MeetingManager.shared.setRustState()...")
                    MeetingManager.shared.setRustState(state)
                    debugLog("✅ Meeting Manager Initialized")
                } catch {
                    debugLog("❌ ML/Meeting initialization failed: \(error)")
                }
            }
    
        // Setup global hotkeys
        self.setupHotKeys()
        
        // Initialize LLM Engine if enabled
        let llmSuffix = SettingsManager.shared.llmProvider != .none ? ", Voice Triggers for AI Skills." : "."
        debugLog("🎤 \(Constants.appName) ready! Hold Right Command to record\(llmSuffix)")
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
    
    @MainActor
    @objc private func onModelSelectionChanged() {
        debugLog("🔄 Settings changed, reinitializing...")
        initializeTranscription()
    }
    
    @MainActor
    @objc private func onMeetingTranscriptUpdated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let text = userInfo["text"] as? String else { return }
        
        let speaker = userInfo["speaker"] as? String // Optional
        
        self.overlayWindow?.updateTranscript(text: text, speaker: speaker)
    }
    
    @objc func importAudioFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = L10n.isFrench ? "Importer" : "Import"
        panel.message = L10n.isFrench ? "Selectionnez un fichier audio (mp3, wav, m4a)" : "Select an audio file (mp3, wav, m4a)"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    // Show Details Window immediately (it works well as a progress viewer since it observes currentMeeting)
                    // We need to trigger the import
                    await MeetingManager.shared.importMeeting(from: url)
                    
                    // After import starts/finishes, ensure we open the window to see it
                    await MainActor.run {
                        self.openMeetingDetails(for: MeetingManager.shared.currentMeeting)
                    }
                }
            }
        }
    }
    
    
    
    @MainActor
    func openMeetingDetails(for meeting: Meeting?) {
        guard let meeting = meeting else { return }
        
        // If window exists, close it (simple single-window policy)
        if let existing = meetingDetailWindow {
            existing.close()
        }
        
        let window = MeetingDetailWindow(meeting: meeting)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false // Keep alive via our reference
        self.meetingDetailWindow = window
    }
    
    private func initializeTranscription() {
        Task { @MainActor in
            do {
                if TranscriptionManager.shared.isReady {
                    debugLog("✅ Parakeet already initialized.")
                    return
                }

                let language = ModelManager.shared.selectedLanguage
                
                debugLog("📦 Initializing Parakeet with language: \(language)")
                try await TranscriptionManager.shared.initialize(language: language)
                debugLog("✅ Parakeet ready!")
            } catch {
                debugLog("❌ Failed to initialize Parakeet: \(error)")
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
    
    @MainActor
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
            debugLog("✅ Microphone access granted")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    debugLog("✅ Microphone access granted")
                } else {
                    debugLog("❌ Microphone access denied")
                }
            }
        case .denied, .restricted:
            debugLog("❌ Microphone access denied/restricted")
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
    
    @MainActor
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Try multiple locations for the icon
            var icon: NSImage?
            var iconSource = "none"
            
            // 1. Try main bundle Resources folder (primary location for bundled app)
            if let iconURL = Bundle.main.url(forResource: "suprasonic-icon-black", withExtension: "png") {
                icon = NSImage(contentsOf: iconURL)
                if icon != nil { iconSource = "main bundle" }
            }
            
            // 2. Try in nested SPM resource bundle (for relocated bundles)
            if icon == nil {
                if let bundleURL = Bundle.main.url(forResource: "SupraSonicApp_SupraSonicApp", withExtension: "bundle"),
                   let resourceBundle = Bundle(url: bundleURL) {
                    if let iconURL = resourceBundle.url(forResource: "suprasonic-icon-black", withExtension: "png") {
                        icon = NSImage(contentsOf: iconURL)
                        if icon != nil { iconSource = "nested SPM bundle" }
                    }
                }
            }
            
            // 3. Try SPM debug build path (bundle next to executable)
            if icon == nil {
                let executablePath = CommandLine.arguments[0]
                let executableURL = URL(fileURLWithPath: executablePath).standardized
                let debugBundleURL = executableURL.deletingLastPathComponent()
                    .appendingPathComponent("SupraSonicApp_SupraSonicApp.bundle")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent("suprasonic-icon-black.png")
                if FileManager.default.fileExists(atPath: debugBundleURL.path) {
                    icon = NSImage(contentsOf: debugBundleURL)
                    if icon != nil { iconSource = "debug build path" }
                }
            }
            
            debugLog("🎨 Status bar icon source: \(iconSource), loaded: \(icon != nil)")
            
            if let icon = icon {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                // Fallback to system symbol
                debugLog("⚠️ Using fallback system symbol for status bar")
                button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: Constants.appName)
                button.image?.isTemplate = true
            }
        }
        
        let menu = NSMenu()
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionItem = NSMenuItem(title: "\(Constants.appName) v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
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
    
    @MainActor
    @objc func openSettings() {
        settingsWindow?.show()
    }
    
    @MainActor
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @MainActor
    @objc func toggleMeeting() {
        if MeetingManager.shared.isMeetingActive {
            MeetingManager.shared.stopMeeting()
            DispatchQueue.main.async {
                self.overlayWindow?.hide()
            }
        } else {
            MeetingManager.shared.startMeeting(title: "Quick Meeting")
            DispatchQueue.main.async {
                self.overlayWindow?.setMeetingMode(true)
                self.overlayWindow?.show()
            }
        }
        updateStatusMenu()
    }
    
    private func updateStatusMenu() {
        // No dynamic menu updates needed since meeting item was removed
    }

    @MainActor
    @objc func showParticipantEnrollment() {
        // Enrollment is now handled in the Réunions tab of Settings
        openSettings()
        // The SettingsWindow will show the enrollment UI directly
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
    
    @MainActor
    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        if let device = sender.representedObject as? AudioDeviceManager.AudioDevice {
            AudioDeviceManager.shared.setInputDevice(device)
            updateMicrophoneMenu()
        }
    }
    
    @MainActor
    func setupHotKeys() {
        let settings = SettingsManager.shared
        let mainKeyCode = settings.pushToTalkKey
        let isMainModifier = isModifierKeyCode(mainKeyCode)
        
        // Monitor for Main Hotkey
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleMainHotkey(event: event, keyCode: mainKeyCode, isModifier: isMainModifier)
        }
        
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleMainHotkey(event: event, keyCode: mainKeyCode, isModifier: isMainModifier)
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
                    debugLog("⌨️ Hotkey: PTT Down")
                    pushToTalkDown = true
                    startRecording()
                } else if keyReleased && pushToTalkDown {
                    debugLog("⌨️ Hotkey: PTT Up")
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
    
    @objc @MainActor private func handleWake() {
        debugLog("☀️ System: Wake detected. Triggering pre-warm...")
        TranscriptionManager.shared.preWarm()
    }
    
    @objc @MainActor private func handleAudioConfigChange() {
        debugLog("🔄 Audio: Configuration change detected.")
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Rust Core Start
        if let state = rustState {
            do {
                try state.startRecording()
                debugLog("🦀 Rust: Start Capture")
            } catch {
                debugLog("❌ Rust Start Failed: \(error)")
            }
        }
        
        isRecording = true
        
        // Capture any selected text from the active app BEFORE we start recording
        capturedSelectedText = getSelectedText()
        if let selected = capturedSelectedText {
            debugLog("📎 App: Captured selected text (\(selected.count) chars): \(selected.prefix(80))...")
        }
        
        // Mute system sound if enabled
        if SettingsManager.shared.muteSystemSoundDuringRecording {
            debugLog("🔇 Muting system audio...")
            // Save current volume and mute
            savedVolumeLevel = getCurrentVolume()
            runAppleScript("set volume output volume 0")
        }
        
        DispatchQueue.main.async {
            self.overlayWindow?.setMeetingMode(false) // Default to regular dictation
            self.overlayWindow?.show()
        }
        
        debugLog("🎙️ Recording started...")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Rust Core Stop
        if let state = rustState {
            do {
                try state.stopRecording()
                debugLog("🦀 Rust: Stop Capture")
            } catch {
                 debugLog("❌ Rust Stop Failed: \(error)")
            }
        }
        
        isRecording = false
        
        // Unmute system sound if enabled
        if SettingsManager.shared.muteSystemSoundDuringRecording {
            let restoreLevel = savedVolumeLevel ?? 50
            debugLog("🔊 Restoring system audio to \(restoreLevel)%")
            runAppleScript("set volume output volume \(restoreLevel)")
            savedVolumeLevel = nil
        }
        
        DispatchQueue.main.async {
            self.overlayWindow?.hide()
        }
        
        debugLog("⏹️ Recording stopped.")
    }
    
    func handleTranscriptionResult(_ text: String) {
        let isConsecutive = lastTranscriptionTime != nil && Date().timeIntervalSince(lastTranscriptionTime!) < Constants.consecutiveTranscriptionThreshold
        lastTranscriptionTime = Date()
        
        KeystrokeManager.shared.insertText(text, consecutive: isConsecutive)
    }

    // MARK: - Rust Integration Helpers
    
    nonisolated func handleAudioBuffer(_ audioData: [Float]) {
        Task { @MainActor in
            // During meetings, transcription is handled by MeetingManager.flushAudio()
            // Also skip for a few seconds after meeting stops to avoid last chunk leaking
            if MeetingManager.shared.isMeetingActive || MeetingManager.shared.recentlyStopped {
                return
            }
            
            do {
                debugLog("🧠 App: Starting Parakeet v3 inference...")
                let text = try await TranscriptionManager.shared.transcribe(audioSamples: audioData)
                
                debugLog("📝 Parakeet Result: \(text)")
                if !text.isEmpty {
                    let finalOutput = text
                    
                    SettingsManager.shared.addToHistory(finalOutput)
                    
                    // Check for AI Skills Triggers
                    let skills = SettingsManager.shared.aiSkills
                    let cleanText = finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?- "))
                    let lowerText = cleanText.lowercased()
                    
                    if let triggeredSkill = skills.first(where: { lowerText.starts(with: $0.trigger.lowercased()) }) {
                        debugLog("🤖 App: AI Skill Triggered: \(triggeredSkill.name)")
                        
                        self.overlayWindow?.updateStatusLabel(L10n.isFrench ? "Assistant IA: Réflexion..." : "AI Assistant: Thinking...")
                        self.overlayWindow?.show()
                        
                        let trigger = triggeredSkill.trigger.lowercased()
                        var inputText = finalOutput
                        if let range = inputText.range(of: trigger, options: [.caseInsensitive]) {
                            inputText.removeSubrange(range)
                        }
                        inputText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let selectedContext = self.capturedSelectedText
                        self.capturedSelectedText = nil
                        Task {
                            do {
                                let result = try await LLMManager.shared.processSkill(skill: triggeredSkill, text: inputText, selectedText: selectedContext)
                                debugLog("🤖 App: AI Skill Result received")
                                
                                await MainActor.run {
                                    self.overlayWindow?.hide()
                                    self.handleTranscriptionResult(result)
                                }
                            } catch {
                                debugLog("❌ App: AI Skill failed: \(error)")
                                await MainActor.run {
                                    self.overlayWindow?.hide()
                                    self.showAPIErrorAlert(error: error)
                                }
                            }
                        }
                    } else {
                        // Regular dictation
                        self.handleTranscriptionResult(finalOutput)
                    }
                }
            } catch {
                debugLog("❌ Transcription failed: \(error)")
            }
        }
    }
    
    nonisolated func handleAudioLevel(_ level: Float) {
        Task { @MainActor in
            self.overlayWindow?.updateLevel(level)
        }
    }
    
    private func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error = error {
                debugLog("❌ AppleScript error: \(error)")
            }
        } else {
            debugLog("❌ AppleScript: Failed to create script from: \(source)")
        }
    }
    
    private func getCurrentVolume() -> Int {
        let script = NSAppleScript(source: "output volume of (get volume settings)")
        var error: NSDictionary?
        if let result = script?.executeAndReturnError(&error) {
            return Int(result.int32Value)
        }
        return 50 // Default fallback
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(Constants.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(Constants.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "H")
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(Constants.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // Edit Menu (CRITICAL for Copy/Paste)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        NSApp.mainMenu = mainMenu
    }
    
    // MARK: - Selected Text Capture
    
    /// Captures the currently selected text from the frontmost application.
    /// Uses clipboard-based approach: saves clipboard → simulates Cmd+C → reads selection → restores clipboard.
    /// Returns nil if no text is selected.
    private func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        
        // 1. Save current clipboard contents
        let savedChangeCount = pasteboard.changeCount
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> [String: Data]? in
            var dict = [String: Data]()
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            return dict.isEmpty ? nil : dict
        } ?? []
        
        // 2. Simulate Cmd+C to copy the selection
        let source = CGEventSource(stateID: .hidSystemState)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'c' key
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        
        // 3. Wait briefly for the clipboard to update
        Thread.sleep(forTimeInterval: 0.1)
        
        // 4. Read the new clipboard content
        var selectedText: String? = nil
        if pasteboard.changeCount != savedChangeCount {
            selectedText = pasteboard.string(forType: .string)
        }
        
        // 5. Restore original clipboard
        pasteboard.clearContents()
        for itemDict in savedItems {
            let item = NSPasteboardItem()
            for (typeString, data) in itemDict {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: typeString))
            }
            pasteboard.writeObjects([item])
        }
        
        // 6. Validate and return
        guard let text = selectedText, !text.isEmpty else {
            return nil
        }
        
        // Truncate very long selections to avoid exceeding LLM token limits
        let maxLength = 4000
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "\n[... truncated]"
        }
        
        return text
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
        debugLog("🎙️ Rust Audio Captured: \(audioData.count) samples")
        
        Task { @MainActor in
            if MeetingManager.shared.isMeetingActive {
                MeetingManager.shared.handleAudioBuffer(audioData)
            }
        }
        
        self.delegate?.handleAudioBuffer(audioData)
    }
    
    func onLevelChanged(level: Float) {
        self.delegate?.handleAudioLevel(level)
    }
}

extension AppDelegate: RustAudioDelegate {}

// MARK: - Error Alerts & Recovery System

extension AppDelegate {
    
    /// Shows an alert for API errors and offers to open settings
    func showAPIErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        
        let nsError = error as NSError
        
        if nsError.domain == "LLMManager" && (nsError.code == 1 || nsError.code == 2) {
            alert.messageText = L10n.isFrench ? "Clé API manquante" : "API Key Missing"
            alert.informativeText = L10n.isFrench
                ? "Aucune clé API n'est configurée pour l'assistant IA.\n\nConfigurez votre clé API dans les paramètres."
                : "No API key is configured for the AI assistant.\n\nConfigure your API key in settings."
        } else if nsError.domain == NSURLErrorDomain {
            alert.messageText = L10n.isFrench ? "Erreur de connexion" : "Connection Error"
            alert.informativeText = L10n.isFrench
                ? "Impossible de contacter le serveur IA.\n\nVérifiez votre connexion Internet."
                : "Unable to reach the AI server.\n\nCheck your internet connection."
        } else {
            alert.messageText = L10n.isFrench ? "Erreur API" : "API Error"
            let errorMsg = nsError.localizedDescription
            let shortMsg = errorMsg.count > 150 ? String(errorMsg.prefix(150)) + "..." : errorMsg
            alert.informativeText = L10n.isFrench
                ? "L'assistant IA a rencontré une erreur :\n\(shortMsg)"
                : "The AI assistant encountered an error:\n\(shortMsg)"
        }
        
        alert.addButton(withTitle: L10n.isFrench ? "Ouvrir les paramètres" : "Open Settings")
        alert.addButton(withTitle: L10n.isFrench ? "Fermer" : "Close")
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            openSettings()
        }
    }
    
    /// Shows a recovery modal when the app detects critical issues.
    /// Offers to reset the app and restart with onboarding.
    func showRecoveryModal(reason: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.isFrench ? "SupraSonic a rencontré un problème" : "SupraSonic encountered a problem"
        
        let defaultReason = L10n.isFrench
            ? "L'application ne fonctionne pas correctement."
            : "The application is not working correctly."
        
        alert.informativeText = L10n.isFrench
            ? "\(reason ?? defaultReason)\n\nVoulez-vous réinitialiser l'application et relancer la configuration ?"
            : "\(reason ?? defaultReason)\n\nWould you like to reset the application and restart the setup?"
        
        alert.addButton(withTitle: L10n.isFrench ? "Réinitialiser et relancer" : "Reset and Restart")
        alert.addButton(withTitle: L10n.isFrench ? "Annuler" : "Cancel")
        
        // Add app icon
        if let icon = NSImage(named: NSImage.applicationIconName) {
            alert.icon = icon
        }
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            performResetAndRestart()
        }
    }
    
    /// Resets app state and restarts with onboarding
    private func performResetAndRestart() {
        // 1. Reset setup completed flag to trigger onboarding
        UserDefaults.standard.set(false, forKey: Constants.Keys.setupCompleted)
        
        // 2. Reset accessibility permission request flag
        UserDefaults.standard.removeObject(forKey: "AppleEventsPermissionRequested")
        
        // 3. Reset paste failure counter
        KeystrokeManager.shared.resetPasteFailureCounter()
        
        // 4. Remove SupraSonic from accessibility permissions via tccutil
        removeAccessibilityPermissions()
        
        // 5. Show confirmation and relaunch
        let confirmAlert = NSAlert()
        confirmAlert.alertStyle = .informational
        confirmAlert.messageText = L10n.isFrench ? "Réinitialisation terminée" : "Reset Complete"
        confirmAlert.informativeText = L10n.isFrench
            ? "L'application va maintenant redémarrer pour relancer la configuration."
            : "The application will now restart to begin setup."
        confirmAlert.addButton(withTitle: "OK")
        confirmAlert.runModal()
        
        // 6. Relaunch the app
        relaunchApp()
    }
    
    /// Removes SupraSonic from accessibility permissions using tccutil
    private func removeAccessibilityPermissions() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.suprasonic.app"
        
        // Use tccutil to reset accessibility permissions for this app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleId]
        
        do {
            try process.run()
            process.waitUntilExit()
            debugLog("✅ Accessibility permissions reset for \(bundleId)")
        } catch {
            debugLog("⚠️ Failed to reset accessibility permissions: \(error)")
        }
    }
    
    /// Relaunches the application
    private func relaunchApp() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

