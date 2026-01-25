import Cocoa
import AVFoundation
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow?
    private var settingsWindow: SettingsWindow?
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var isRecording = false
    private var pushToTalkDown = false
    private var converter: AVAudioConverter?
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var toggleKeyDown = false  // Track toggle key state for toggle mode
    
    private let targetSampleRate: Double = 16000
    private let maxBufferSamples = 16000 * 60  // Max 60 seconds of audio
    private var lastUIUpdate: CFTimeInterval = 0
    private let uiUpdateInterval: CFTimeInterval = 1.0/30.0 // 30 FPS
    
    // Tracking for consecutive transcriptions
    private var lastTranscriptionTime: Date? = nil
    private let consecutiveThreshold: TimeInterval = 30.0 // 30 seconds
    
    private var setupWindow: SetupWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Check system compatibility
        if !checkCompatibility() {
            return
        }
        
        // 2. Create windows
        overlayWindow = OverlayWindow()
        settingsWindow = SettingsWindow()
        
        // Listen for hotkey settings changes
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeySettingsChanged), name: .hotkeySettingsChanged, object: nil)
        
        // Listen for model selection changes
        NotificationCenter.default.addObserver(self, selector: #selector(onModelSelectionChanged), name: .modelSelectionChanged, object: nil)
        
        // Listen for setup completion
        NotificationCenter.default.addObserver(self, selector: #selector(onSetupComplete), name: NSNotification.Name("SetupComplete"), object: nil)
        
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
        let setupCompleted = UserDefaults.standard.bool(forKey: "SupraSonicSetupCompleted")
        if !setupCompleted {
            print("🚀 App: Onboarding never completed. Showing setup.")
            return true
        }
        
        // 2. Check system-level requirements
        let hasPermissions = PermissionsManager.shared.checkMicrophonePermission() == .granted
        let hasModel = ModelManager.shared.hasAnyModel()
        let isInApplications = Bundle.main.bundleURL.path.hasPrefix("/Applications")
        
        // 3. If everything is OK, don't show setup
        if hasPermissions && hasModel && (isInApplications || !Bundle.main.bundleURL.path.contains(".dmg")) {
            return false
        }
        
        // 4. Force setup if critical pieces are missing, even if "completed" before
        print("🚀 App: Setup completed but requirements missing. Re-showing setup.")
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
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SetupComplete"), object: nil)
        
        // 2. Mark as completed in UserDefaults
        UserDefaults.standard.set(true, forKey: "SupraSonicSetupCompleted")
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
        // Setup audio engine
        self.setupAudioEngine()
        
        // Setup global hotkeys
        self.setupHotKeys()
        
        // Initialize Parakeet
        self.initializeTranscription()
        
        print("🎤 SupraSonic ready! Hold Right Command to record.")
    }
    
    private func checkCompatibility() -> Bool {
        // Check macOS version (Minimum 14.0 Sonoma)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion < 14 {
            let alert = NSAlert()
            alert.messageText = L10n.isFrench ? "Version macOS non supportée" : "Unsupported macOS Version"
            alert.informativeText = L10n.isFrench 
                ? "SupraSonic nécessite macOS 14.0 (Sonoma) ou plus récent pour fonctionner avec le moteur Parakeet."
                : "SupraSonic requires macOS 14.0 (Sonoma) or newer to run with the Parakeet engine."
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
            ? "SupraSonic est optimisé pour les processeurs Apple Silicon (M1, M2, M3, M4). Les processeurs Intel ne sont pas supportés par le moteur de transcription actuel."
            : "SupraSonic is optimized for Apple Silicon processors (M1, M2, M3, M4). Intel processors are not supported by the current transcription engine."
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
            alert.informativeText = "SupraSonic needs microphone access to transcribe your speech. Please enable it in System Settings > Privacy & Security > Microphone."
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
            // NOTE: We avoid Bundle.module here because it contains a fatalError assertion 
            // in generated SPM code if the resource bundle is missing, which causes 
            // a crash during development or when run from the build folder.
            if let iconURL = Bundle.main.url(forResource: "suprasonic-icon-black", withExtension: "png") {
                icon = NSImage(contentsOf: iconURL)
            }
            
            // 2. Try in nested SPM resource bundle (for relocated bundles)
            if icon == nil {
                if let bundleURL = Bundle.main.url(forResource: "SupraSonicApp_SupraSonicApp", withExtension: "bundle"),
                   let resourceBundle = Bundle(url: bundleURL) {
                    if let iconURL = resourceBundle.url(forResource: "suprasonic-icon-black", withExtension: "png") {
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
                button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "SupraSonic")
                button.image?.isTemplate = true
            }
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "SupraSonic", action: nil, keyEquivalent: ""))
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
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        // Modifier key codes: Command (L/R), Shift (L/R), Option (L/R), Control (L/R)
        return [0x36, 0x37, 0x38, 0x3C, 0x3A, 0x3D, 0x3B, 0x3E].contains(keyCode)
    }
    
    private func isModifierActive(event: NSEvent, keyCode: UInt16) -> Bool {
        switch keyCode {
        case 0x36: // Right Command
            return (event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK)) != 0
        case 0x37: // Left Command
            return (event.modifierFlags.rawValue & UInt(NX_DEVICELCMDKEYMASK)) != 0
        case 0x38: // Left Shift
            return (event.modifierFlags.rawValue & UInt(NX_DEVICELSHIFTKEYMASK)) != 0
        case 0x3C: // Right Shift
            return (event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK)) != 0
        case 0x3A: // Left Option
            return (event.modifierFlags.rawValue & UInt(NX_DEVICELALTKEYMASK)) != 0
        case 0x3D: // Right Option
            return (event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK)) != 0
        case 0x3B: // Left Control
            return (event.modifierFlags.rawValue & UInt(NX_DEVICELCTLKEYMASK)) != 0
        case 0x3E: // Right Control
            return (event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK)) != 0
        default:
            return false
        }
    }
    
    @objc private func handleWake() {
        print("☀️ System: Wake detected. Restarting audio engine...")
        restartAudioEngine()
    }
    
    @objc private func handleAudioConfigChange() {
        print("🔄 Audio: Configuration change detected. Recovering...")
        restartAudioEngine()
    }
    
    private func restartAudioEngine() {
        // Stop current engine and remove taps
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        
        // Nuillify and rebuild
        audioEngine = nil
        converter = nil
        
        // Re-setup engine
        setupAudioEngine()
    }
    
    func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!
        
        // Create converter once for reuse
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        
        // Larger buffer for efficiency
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }
            self.processAudioBuffer(buffer, targetFormat: targetFormat)
        }
        
        do {
            try audioEngine.start()
            print("✅ Audio engine started")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter = converter else { return }
        
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else { return }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
        let level = samples.map { abs($0) }.max() ?? 0
        
        // Append samples (thread-safe via main queue, but throttle UI updates)
        DispatchQueue.main.async {
            self.audioBuffer.append(contentsOf: samples)
            
            // Limit buffer size to prevent memory issues
            if self.audioBuffer.count > self.maxBufferSamples {
                self.audioBuffer.removeFirst(self.audioBuffer.count - self.maxBufferSamples)
            }
            
            // Throttle UI updates to reduce CPU usage
            let now = CACurrentMediaTime()
            if now - self.lastUIUpdate >= self.uiUpdateInterval {
                self.lastUIUpdate = now
                self.overlayWindow?.updateLevel(level)
            }
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Safety check: ensure engine is running
        if let engine = audioEngine, !engine.isRunning {
            print("⚠️ Engine wasn't running, attempting to start...")
            try? engine.start()
        }
        
        isRecording = true
        audioBuffer.removeAll()
        
        DispatchQueue.main.async {
            self.overlayWindow?.show()
        }
        
        print("🎙️ Recording started...")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        
        DispatchQueue.main.async {
            self.overlayWindow?.hide()
        }
        
        print("⏹️ Recording stopped. Samples: \(audioBuffer.count)")
        
        // Send to WhisperKit for transcription
        if !audioBuffer.isEmpty {
            transcribeAudio()
        }
    }
    
    func transcribeAudio() {
        let samples = audioBuffer
        audioBuffer.removeAll()
        
        Task {
            do {
                // Check if WhisperKit is ready (on MainActor)
                let isReady = await TranscriptionManager.shared.isReady
                if !isReady {
                    print("⚠️ WhisperKit not ready, initializing...")
                    try await TranscriptionManager.shared.initialize()
                }
                
                let text = try await TranscriptionManager.shared.transcribe(audioSamples: samples)
                
                if !text.isEmpty {
                    print("📝 Transcription: \(text)")
                    
                    // Save to history if enabled
                    await MainActor.run {
                        SettingsManager.shared.addToHistory(text)
                        self.insertText(text)
                    }
                }
            } catch {
                print("❌ Transcription failed: \(error)")
            }
        }
    }
    
    func insertText(_ text: String) {
        var textToInsert = text
        
        // Add a leading space if we transcribed recently (consecutive dictation)
        if let lastTime = lastTranscriptionTime, Date().timeIntervalSince(lastTime) < consecutiveThreshold {
            textToInsert = " " + textToInsert
            print("✨ Adding leading space for consecutive transcription")
        }
        
        lastTranscriptionTime = Date()
        
        // 1. Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToInsert, forType: .string)
        
        print("📋 [DEBUG] Text copied to clipboard (\(textToInsert.count) chars): \(textToInsert.prefix(30))...")
        
        // Check environment
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        print("📦 [DEBUG] App Context - Sandboxed: \(isSandboxed), Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
        
        // 2. Try to paste with a brief delay (100ms) to ensure clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            var pasteSucceeded = false
            let hasRequestedAppleEvents = UserDefaults.standard.bool(forKey: "AppleEventsPermissionRequested")
            
            if !hasRequestedAppleEvents {
                print("📋 [DEBUG] AppleScript attempt - First launch logic...")
                let script = """
                tell application "System Events"
                    keystroke "v" using command down
                end tell
                """
                
                let appleScript = NSAppleScript(source: script)
                var error: NSDictionary?
                appleScript?.executeAndReturnError(&error)
                
                if error == nil {
                    print("✅ [DEBUG] AppleScript execution reported success")
                    pasteSucceeded = true
                    UserDefaults.standard.set(true, forKey: "AppleEventsPermissionRequested")
                } else {
                    print("⚠️ [DEBUG] AppleScript failed: \(error ?? [:])")
                    // Don't set the flag to true if it was an error that might be recoverable or prompted
                    if let errNum = error?[NSAppleScript.errorNumber] as? Int, errNum == -1728 {
                        // System Events not found or similar hard error
                        UserDefaults.standard.set(true, forKey: "AppleEventsPermissionRequested")
                    }
                }
            } else {
                print("📋 [DEBUG] Skipping AppleScript (using fallback mode)")
            }
            
            // 3. Fallback to CGEvent if AppleScript skipped or failed
            if !pasteSucceeded {
                self.performPasteViaCGEvent()
            }
        }
    }
    
    private func performPasteViaCGEvent() {
        let isTrusted = AXIsProcessTrusted()
        print("🎯 [DEBUG] CGEvent Fallback - Accessibility Trusted: \(isTrusted)")
        
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdKey: UInt16 = 0x37 // Left Command
        let vKey: UInt16 = 0x09   // 'v'
        
        guard let pbtDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true),
              let pbtUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            print("❌ [DEBUG] Failed to create CGEvents")
            return
        }
        
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        
        // Full sequence: Cmd Down -> V Down -> V Up -> Cmd Up
        pbtDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        pbtUp.post(tap: .cghidEventTap)
        
        print("🎯 [DEBUG] Full CGEvent sequence posted (Cmd + V)")
    }
}

