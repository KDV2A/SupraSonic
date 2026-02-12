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
    private var tipLabel: NSTextField!
    
    
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
    
    private var aiChoiceContainer: NSStackView!
    private var aiTitleLabel: NSTextField!
    private var aiDescLabel: NSTextField!
    private var enableAIButton: NSButton!
    private var skipAIButton: NSButton!
    private var aiContinuation: CheckedContinuation<Bool, Never>?
    
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
        logoView.image = NSApp.applicationIconImage
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
        
        container.addArrangedSubview(logoView)
        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(descLabel)
        container.addArrangedSubview(progressStack)
        container.addArrangedSubview(actionButton)
        
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
        debugLog("🚀 Setup: Start clicked")
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
                // Automate repair instead of showing error
                updateStatus(L10n.isFrench ? "Réparation des permissions..." : "Repairing permissions...", progress: 40)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s delay
                
                PermissionsManager.shared.resetAccessibility()
                PermissionsManager.shared.relaunchApp()
                return
            }
            
            // 3.5 NO LLM SETUP REQUIRED FOR API
            // API setup is handled in Settings now.
            SettingsManager.shared.llmProvider = .none // Default to none, user can enable APIKey later
            
            // 4. Download Model (Transcription Only)
            self.level = .floating // Stay on top during download
            updateStatus(l.setupDownloadParakeet, progress: 45)
            DispatchQueue.main.async { self.progressLabel.isHidden = false }
            
            // Track progress based on actual status and progress from TranscriptionManager
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    let tm = TranscriptionManager.shared
                    let engineStatus = tm.statusMessage
                    let actualProgress = tm.progress * 100.0
                    
                    if engineStatus.isEmpty { return }
                    
                    if self.progressBar.doubleValue < actualProgress {
                        let diff = actualProgress - self.progressBar.doubleValue
                        self.progressBar.doubleValue += min(diff * 0.2, 5.0)
                    } else if self.progressBar.doubleValue > actualProgress + 1.0 {
                        self.progressBar.doubleValue = actualProgress
                    }
                    
                    self.statusLabel.stringValue = engineStatus
                    
                    // Approximation since we don't track total size perfectly here anymore
                    let percent = Int(self.progressBar.doubleValue)
                    self.progressLabel.stringValue = "\(percent)%"
                }
            }
            
            do {
                debugLog("📥 Setup: Starting transcription engine initialization...")
                try await TranscriptionManager.shared.initialize()
                debugLog("✅ Setup: Initialization successful")
                
                // Initialize LLM Manager (Access Check)
                try await LLMManager.shared.initialize()
                
                progressTimer.invalidate()
                
                // Animate to 100%
                DispatchQueue.main.async {
                    self.progressBar.doubleValue = 100
                    self.progressLabel.stringValue = "100%"
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                finishSuccess()
            } catch {
                debugLog("❌ Setup: Initialization failed: \(error)")
                progressTimer.invalidate()
                showError("\(l.setupError): \(error.localizedDescription)")
            }
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
        debugLog("✅ Setup: Success finish clicked")
        
        // Disable animations to prevent crash during tear-down
        self.animationBehavior = .none
        self.orderOut(nil)
        
        // Post notification asynchronously to ensure current event processing finishes
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Constants.NotificationNames.setupComplete, object: nil)
        }
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
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
                attempts += 1
                
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    continuation.resume(returning: true)
                } else if attempts > 15 { // 30 seconds timeout
                    timer.invalidate()
                    continuation.resume(returning: false)
                }
            }
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
