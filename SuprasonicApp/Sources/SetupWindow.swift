import Cocoa
import AVFoundation

class SetupWindow: NSWindow {
    private var container: NSStackView!
    private var logoView: NSImageView!
    private var titleLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var actionButton: NSButton!
    private var progressLabel: NSTextField!
    private var troubleshootButton: NSButton!
    private var tipLabel: NSTextField!
    
    private var llmContinuation: CheckedContinuation<Bool, Never>?
    
    private let brandBlue = Constants.brandBlue
    private let totalModelSizeMB = Constants.modelSizeMB
    
    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 450, height: 400)
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = .windowBackgroundColor
        self.level = .normal
        self.center()
        
        setupUI()
        
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
    }
    
    private func setupUI() {
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .sidebar
        self.contentView = visualEffect
        
        container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 25
        visualEffect.addSubview(container)
        
        let l = L10n.current
        
        // Logo
        logoView = NSImageView()
        logoView.translatesAutoresizingMaskIntoConstraints = false
        if let logo = NSImage(named: "icon_512x512@2x.png") {
            logoView.image = logo
        } else if let fallbackLogo = NSImage(named: "AppIcon.icns") {
             logoView.image = fallbackLogo
        } else {
            logoView.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)
            logoView.contentTintColor = brandBlue
        }
        logoView.imageScaling = .scaleProportionallyUpOrDown
        
        // Title
        titleLabel = NSTextField(labelWithString: Constants.appName)
        titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .labelColor
        
        // Description
        let descLabel = NSTextField(labelWithString: l.setupDesc)
        descLabel.font = NSFont.systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.maximumNumberOfLines = 2
        
        // Progress Container
        let progressStack = NSStackView()
        progressStack.orientation = .vertical
        progressStack.spacing = 10
        progressStack.alignment = .centerX
        
        statusLabel = NSTextField(labelWithString: l.setupDiskCheck)
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        
        progressBar = NSProgressIndicator()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        progressBar.controlSize = .large
        
        progressLabel = NSTextField(labelWithString: "0% (0 Mo / \(Int(totalModelSizeMB)) Mo)")
        progressLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.isHidden = true
        
        tipLabel = NSTextField(wrappingLabelWithString: "")
        tipLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.alignment = .center
        tipLabel.isHidden = true
        
        progressStack.addArrangedSubview(statusLabel)
        progressStack.addArrangedSubview(progressBar)
        progressStack.addArrangedSubview(progressLabel)
        progressStack.addArrangedSubview(tipLabel)
        
        // Button
        actionButton = NSButton(title: l.setupGetStarted, target: self, action: #selector(startSetup))
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large
        actionButton.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        actionButton.keyEquivalent = "\r"
        
        troubleshootButton = NSButton(title: l.accessibilityTroubleshootTitle, target: self, action: #selector(showTroubleshooting))
        troubleshootButton.bezelStyle = .recessed
        troubleshootButton.controlSize = .small
        troubleshootButton.font = NSFont.systemFont(ofSize: 12)
        troubleshootButton.isHidden = true
        
        container.addArrangedSubview(logoView)
        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(descLabel)
        container.addArrangedSubview(progressStack)
        container.addArrangedSubview(actionButton)
        container.addArrangedSubview(troubleshootButton)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            container.widthAnchor.constraint(equalTo: visualEffect.widthAnchor, multiplier: 0.85),
            
            logoView.widthAnchor.constraint(equalToConstant: 80),
            logoView.heightAnchor.constraint(equalToConstant: 80),
            
            progressBar.widthAnchor.constraint(equalTo: container.widthAnchor)
        ])
    }
    
    @objc private func startSetup() {
        print("🚀 Setup: Start clicked")
        actionButton.isEnabled = false
        performSetup()
    }
    
    private func performSetup() {
        let l = L10n.current
        Task {
            resetError()
            
            // 1. Check Disk Space
            updateStatus(l.setupDiskCheck, progress: 10)
            if !hasEnoughDiskSpace() {
                showError(l.setupInsufficientSpace)
                return
            }
            
            // 2. Microphone Permission
            updateStatus(l.setupMicrophoneStep, progress: 30)
            let hasMic = await requestMicrophonePermission()
            
            // Re-activate app after prompt
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            
            if !hasMic {
                showError(l.micPermissionDenied)
                return
            }
            
            // 3. Accessibility Permission
            updateStatus(l.setupAccessibilityStep, progress: 40)
            let hasAccess = await requestAccessibilityPermission()
            
            // Re-activate app after prompt
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            
            if !hasAccess {
                showError(l.accessibilityRequiredTitle)
                return
            }
            
            // 3.5 Ask for LLM Activation
            let useLLM = await askForLLM()
            SettingsManager.shared.llmEnabled = useLLM
            
            // 4. Download Model
            self.level = .floating // Stay on top during download
            updateStatus(l.setupDownloadParakeet, progress: 40)
            DispatchQueue.main.async { self.progressLabel.isHidden = false }
            
            // Track progress based on actual status and progress from TranscriptionManager
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    let tm = TranscriptionManager.shared
                    let engineStatus = tm.statusMessage
                    let actualProgress = tm.progress * 100.0 // 0-1 range to 0-100
                    
                    if engineStatus.isEmpty { return }
                    
                    // Smooth animation towards the actual reported progress
                    if self.progressBar.doubleValue < actualProgress {
                        let diff = actualProgress - self.progressBar.doubleValue
                        // Faster acceleration if the gap is large, but still smooth
                        self.progressBar.doubleValue += min(diff * 0.2, 5.0)
                    } else if self.progressBar.doubleValue > actualProgress + 1.0 {
                        // Allow small corrections if it overshoots slightly from a sudden jump
                        self.progressBar.doubleValue = actualProgress
                    }
                    
                    self.statusLabel.stringValue = engineStatus
                    
                    let mb = (self.progressBar.doubleValue / 100.0) * self.totalModelSizeMB
                    let percent = Int(self.progressBar.doubleValue)
                    self.progressLabel.stringValue = "\(percent)% (\(Int(mb)) Mo / \(Int(self.totalModelSizeMB)) Mo)"
                }
            }
            
            do {
                print("📥 Setup: Starting transcription engine initialization...")
                try await TranscriptionManager.shared.initialize()
                print("✅ Setup: Initialization successful")
                progressTimer.invalidate()
                
                // Animate to 100%
                DispatchQueue.main.async {
                    self.progressBar.doubleValue = 100
                    self.progressLabel.stringValue = "100% (\(Int(self.totalModelSizeMB)) Mo / \(Int(self.totalModelSizeMB)) Mo)"
                    // Final sleep to show 100%
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                finishSuccess()
            } catch {
                print("❌ Setup: Initialization failed: \(error)")
                progressTimer.invalidate()
                showError("\(l.setupError): \(error.localizedDescription)")
            }
            
            // 5. Download LLM if enabled
            if SettingsManager.shared.llmEnabled {
                updateStatus(l.setupDownloadParakeet, progress: 90)
                statusLabel.stringValue = "Initializing LLM Engine..."
                do {
                    try await LLMManager.shared.initialize()
                } catch {
                    print("⚠️ LLM Initialization failed: \(error)")
                    // Don't block the whole setup, but inform the user
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "LLM Initialization Warning"
                        alert.informativeText = "The AI Reasoning mode could not be initialized (Missing Metal Shaders). Standard mode will still work. Installing Xcode may resolve this.\n\nError: \(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Continue")
                        alert.runModal()
                        
                        SettingsManager.shared.llmEnabled = false
                    }
                }
            }
            
            finishSuccess()
        }
    }
    
    private func askForLLM() async -> Bool {
        let l = L10n.current
        return await withCheckedContinuation { continuation in
            self.llmContinuation = continuation
            
            DispatchQueue.main.async {
                self.statusLabel.stringValue = l.setupLLMTitle
                self.tipLabel.stringValue = l.setupLLMDesc
                self.tipLabel.isHidden = false
                
                self.actionButton.title = l.setupLLMEnable
                self.actionButton.action = #selector(self.confirmLLM)
                self.actionButton.isEnabled = true
                
                self.troubleshootButton.title = l.setupLLMSkip
                self.troubleshootButton.action = #selector(self.skipLLM)
                self.troubleshootButton.isHidden = false
                self.troubleshootButton.bezelStyle = .rounded
            }
        }
    }
    
    @objc private func confirmLLM() {
        llmContinuation?.resume(returning: true)
        llmContinuation = nil
        prepareForDownload()
    }
    
    @objc private func skipLLM() {
        llmContinuation?.resume(returning: false)
        llmContinuation = nil
        prepareForDownload()
    }
    
    private func prepareForDownload() {
        DispatchQueue.main.async {
            self.actionButton.isEnabled = false
            self.actionButton.action = #selector(self.startSetup)
            self.troubleshootButton.isHidden = true
            self.troubleshootButton.bezelStyle = .recessed
            self.tipLabel.isHidden = true
        }
    }
    
    private func finishSuccess() {
        DispatchQueue.main.async {
            self.level = .normal
            self.statusLabel.stringValue = L10n.isFrench ? "Installation terminée avec succès !" : "Installation complete!"
            self.statusLabel.textColor = .labelColor
            self.progressBar.isHidden = true
            self.progressLabel.isHidden = true
            
            self.actionButton.title = L10n.isFrench ? "Commencer" : "Start Using \(Constants.appName)"
            self.actionButton.isEnabled = true
            self.actionButton.isHidden = false
            self.actionButton.action = #selector(self.finishSetup)
            
            // Show Magic Key Tip
            self.tipLabel.stringValue = L10n.current.setupMagicKeyTip
            self.tipLabel.isHidden = false
        }
    }
    
    @objc private func finishSetup() {
        print("✅ Setup: Success finish clicked")
        NotificationCenter.default.post(name: Constants.NotificationNames.setupComplete, object: nil)
    }
    
    private func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func requestAccessibilityPermission() async -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if accessEnabled {
            return true
        }
        
        return await withCheckedContinuation { continuation in
            var attempts = 0
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                attempts += 1
                
                // Show troubleshoot button after 10 seconds of waiting
                if attempts == 5 {
                    DispatchQueue.main.async {
                        self?.troubleshootButton.isHidden = false
                    }
                }
                
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    DispatchQueue.main.async { self?.troubleshootButton.isHidden = true }
                    continuation.resume(returning: true)
                } else if attempts > 60 {
                    timer.invalidate()
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    @objc private func showTroubleshooting() {
        let l = L10n.current
        let alert = NSAlert()
        alert.messageText = l.accessibilityTroubleshootTitle
        alert.informativeText = l.accessibilityTroubleshootMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: l.accessibilityRepairAndRelaunch)
        alert.addButton(withTitle: l.cancel)
        
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsManager.shared.resetAccessibility()
            PermissionsManager.shared.relaunchApp()
        }
    }
    
    private func updateStatus(_ message: String, progress: Double) {
        DispatchQueue.main.async {
            self.statusLabel.stringValue = message
            self.progressBar.doubleValue = progress
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.statusLabel.stringValue = message
            self.statusLabel.textColor = .systemRed
            self.progressLabel.isHidden = true
            self.actionButton.title = L10n.isFrench ? "Réessayer" : "Retry"
            self.actionButton.isEnabled = true
            self.actionButton.action = #selector(self.startSetup)
        }
    }
    
    private func hasEnoughDiskSpace() -> Bool {
        let fileAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        if let freeSize = fileAttributes?[.systemFreeSize] as? Int64 {
            return freeSize > 2_000_000_000
        }
        return false
    }
    
    private func resetError() {
        DispatchQueue.main.async {
            self.statusLabel.textColor = .secondaryLabelColor
            self.statusLabel.stringValue = ""
            self.actionButton.title = L10n.current.setupGetStarted
            self.actionButton.isEnabled = false
        }
    }
}
