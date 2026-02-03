import Cocoa
import Carbon.HIToolbox
import AVFoundation
import Combine

class SettingsWindow: NSWindow {
    private var sidebarView: SidebarView!
    private var contentContainer: NSView!
    private var sidebarEffectView: NSVisualEffectView!
    private var currentSectionView: NSView?
    
    // Cached views for sections
    private var generalView: NSView!
    private var historyView: NSView!
    private var aiView: NSView!
    private var vocabularyView: NSView!
    
    // Configuration controls
    private var historyToggle: NSSwitch!
    private var launchOnLoginToggle: NSSwitch!
    private var muteToggle: NSSwitch!
    private var microphonePopup: NSPopUpButton!
    private var pttCard: ModeCardView!
    private var toggleCard: ModeCardView!
    private var hotkeyButton: HotkeyButton!
    private var aiModesStack: NSStackView!
    private var llmProviderPopup: NSPopUpButton!
    private var apiKeyStack: NSStackView!
    private var apiKeyField: NSTextField!
    private var localModelLabel: NSTextField!
    private var cloudModelLabel: NSTextField!
    private var statusIndicator: NSImageView!
    
    // Model controls (simplified for FluidAudio)
    private var languagePopup: NSPopUpButton!
    
    // Vocabulary controls
    private var vocabularyTableView: NSTableView!
    private var vocabularyData: [(spoken: String, corrected: String)] = []
    
    // History controls
    private var historyTableView: NSTableView!
    private var historyScrollView: NSScrollView!
    private var historyData: [TranscriptionEntry] = []
    
    // Local AI Controls
    private var localAIToggle: NSSwitch!
    private var downloadProgressBar: NSProgressIndicator!
    private var downloadProgressLabel: NSTextField!
    private var downloadButton: NSButton!
    private var cancellables = Set<AnyCancellable>()
    

    private let l = L10n.current
    
    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 950, height: 600)
        
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.title = l.settingsTitle
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.center()
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 900, height: 550)
        
        // Setup initial UI structure
        setupUI()
        loadSettings()
        
        // Select first section by default
        switchToSection(.config)
        
        NotificationCenter.default.addObserver(self, selector: #selector(onHistoryEntryAdded(_:)), name: Constants.NotificationNames.historyEntryAdded, object: nil)
    }
    
    

    
    @objc private func onHistoryEntryAdded(_ notification: Notification) {
        if let entry = notification.object as? TranscriptionEntry {
            DispatchQueue.main.async {
                self.addHistoryEntry(entry)
            }
        }
    }

    private func setupUI() {
        let mainContentView = NSView()
        self.contentView = mainContentView
        
        // 1. Sidebar Background (Floating Glass)
        sidebarEffectView = NSVisualEffectView()
        sidebarEffectView.translatesAutoresizingMaskIntoConstraints = false
        sidebarEffectView.material = .underWindowBackground
        sidebarEffectView.blendingMode = .behindWindow
        sidebarEffectView.state = .active
        sidebarEffectView.wantsLayer = true
        sidebarEffectView.layer?.cornerRadius = 16
        mainContentView.addSubview(sidebarEffectView)
        
        // 2. Sidebar View
        sidebarView = SidebarView()
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.onSectionSelected = { [weak self] section in
            self?.switchToSection(section)
        }
        mainContentView.addSubview(sidebarView)
        
        // 3. Content Container
        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.addSubview(contentContainer)
        
        // Pre-create some views
        generalView = createGeneralView()
        historyView = createHistoryView()
        aiView = createAIView()
        vocabularyView = createVocabularyView()
        
        NSLayoutConstraint.activate([
            sidebarEffectView.topAnchor.constraint(equalTo: mainContentView.topAnchor, constant: 48),
            sidebarEffectView.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor, constant: 16),
            sidebarEffectView.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor, constant: -16),
            sidebarEffectView.widthAnchor.constraint(equalToConstant: 220),
            
            sidebarView.topAnchor.constraint(equalTo: sidebarEffectView.topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: sidebarEffectView.leadingAnchor),
            sidebarView.trailingAnchor.constraint(equalTo: sidebarEffectView.trailingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: sidebarEffectView.bottomAnchor),
            
            contentContainer.topAnchor.constraint(equalTo: mainContentView.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: sidebarEffectView.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor)
        ])
    }
    
    enum SettingsSection: Int, CaseIterable {
        case config, ai, vocabulary, history
        
        var title: String {
            let l = L10n.current
            switch self {
            case .config: return l.generalTab
            case .history: return l.historyTab
            case .ai: return L10n.isFrench ? "Compétences IA" : "AI Skills"
            case .vocabulary: return l.vocabularyTab
            }
        }
        
        var iconName: String {
            switch self {
            case .config: return "gearshape.fill"
            case .history: return "clock.arrow.circlepath"
            case .ai: return "wand.and.stars"
            case .vocabulary: return "text.book.closed.fill"
            }
        }
    }
    
    private func switchToSection(_ section: SettingsSection) {
        let targetView: NSView
        switch section {
        case .config: targetView = generalView
        case .history: targetView = historyView
        case .ai: targetView = aiView
        case .vocabulary: targetView = vocabularyView
        }
        
        if currentSectionView == targetView { return }
        
        // Smooth transition
        targetView.translatesAutoresizingMaskIntoConstraints = false
        targetView.alphaValue = 0
        contentContainer.addSubview(targetView)
        
        NSLayoutConstraint.activate([
            targetView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            targetView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            targetView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            targetView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            currentSectionView?.animator().alphaValue = 0
            targetView.animator().alphaValue = 1
        } completionHandler: {
            self.currentSectionView?.removeFromSuperview()
            self.currentSectionView = targetView
        }
        
        sidebarView.selectSection(section)
    }
    
    private func createGeneralView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        let mainStack = NSStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 24
        mainStack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        
        // 1. Branding Section
        let logoView = NSImageView()
        logoView.image = NSApp.applicationIconImage
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.imageScaling = .scaleProportionallyDown
        
        let titleLabel = NSTextField(labelWithString: "SupraSonic")
        titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .labelColor
        
        let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: "Version \(versionStr)")
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        
        let updateBtn = NSButton(title: L10n.isFrench ? "Vérifier les mises à jour" : "Check for Updates", target: nil, action: nil)
        updateBtn.bezelStyle = .rounded
        updateBtn.isEnabled = false
        
        let brandStack = NSStackView(views: [logoView, titleLabel, versionLabel, updateBtn])
        brandStack.orientation = .vertical
        brandStack.alignment = .centerX
        brandStack.spacing = 10
        brandStack.translatesAutoresizingMaskIntoConstraints = false
        
        let brandContainer = NSView()
        brandContainer.translatesAutoresizingMaskIntoConstraints = false
        brandContainer.addSubview(brandStack)
        
        NSLayoutConstraint.activate([
            logoView.widthAnchor.constraint(equalToConstant: 80),
            logoView.heightAnchor.constraint(equalToConstant: 80),
            brandStack.topAnchor.constraint(equalTo: brandContainer.topAnchor),
            brandStack.centerXAnchor.constraint(equalTo: brandContainer.centerXAnchor),
            brandStack.bottomAnchor.constraint(equalTo: brandContainer.bottomAnchor),
            brandContainer.widthAnchor.constraint(equalToConstant: 550)
        ])
        
        let brandWrapper = NSStackView(views: [brandContainer])
        brandWrapper.alignment = .centerX
        brandWrapper.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(brandWrapper)
        
        NSLayoutConstraint.activate([
            brandWrapper.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            brandWrapper.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor)
        ])
        
        mainStack.setCustomSpacing(40, after: brandWrapper)

        // 2. Keyboard Shortcuts Section
        mainStack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "Raccourci clavier" : "Keyboard shortcut"))
        
        let cardsStack = NSStackView()
        cardsStack.translatesAutoresizingMaskIntoConstraints = false
        cardsStack.orientation = .horizontal
        cardsStack.distribution = .fillEqually
        cardsStack.spacing = 16
        
        pttCard = ModeCardView(title: l.hotkeyModePTT, description: l.pushToTalkDesc, iconName: "mic.fill", mode: .pushToTalk)
        pttCard.target = self
        pttCard.action = #selector(hotkeyModeCardSelected(_:))
        
        toggleCard = ModeCardView(title: l.hotkeyModeToggle, description: l.recordToggleDesc, iconName: "record.circle", mode: .toggle)
        toggleCard.target = self
        toggleCard.action = #selector(hotkeyModeCardSelected(_:))
        
        cardsStack.addArrangedSubview(pttCard)
        cardsStack.addArrangedSubview(toggleCard)
        
        NSLayoutConstraint.activate([
            cardsStack.heightAnchor.constraint(equalToConstant: 140),
            cardsStack.widthAnchor.constraint(equalToConstant: 480)
        ])
        
        let cardsRow = NSStackView(views: [cardsStack])
        cardsRow.translatesAutoresizingMaskIntoConstraints = false
        cardsRow.alignment = .centerX
        cardsRow.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        
        let pttRow = createSettingRow(
            title: l.magicKey,
            description: l.magicKeyDesc,
            control: {
                let button = HotkeyButton()
                button.translatesAutoresizingMaskIntoConstraints = false
                button.target = self
                button.action = #selector(self.hotkeyChanged)
                self.hotkeyButton = button
                return button
            }()
        )
        
        let shortcutsBox = SettingsGroupBox(rows: [cardsRow, pttRow])
        mainStack.addArrangedSubview(shortcutsBox)
        shortcutsBox.widthAnchor.constraint(equalToConstant: 580).isActive = true
        mainStack.setCustomSpacing(24, after: shortcutsBox)

        // 3. Microphone Section
        mainStack.addArrangedSubview(createSectionHeader(l.microphone))
        let microBox = SettingsGroupBox(rows: [
            createSettingRow(
                title: l.microphone,
                description: l.microphoneDesc,
                control: {
                    let popup = NSPopUpButton()
                    popup.translatesAutoresizingMaskIntoConstraints = false
                    popup.font = NSFont.systemFont(ofSize: 13)
                    popup.target = self
                    popup.action = #selector(self.microphoneChanged)
                    self.microphonePopup = popup
                    self.loadMicrophones()
                    return popup
                }()
            )
        ])
        mainStack.addArrangedSubview(microBox)
        microBox.widthAnchor.constraint(equalToConstant: 580).isActive = true
        mainStack.setCustomSpacing(24, after: microBox)

        // 4. Options Section
        mainStack.addArrangedSubview(createSectionHeader(l.optionsSection))
        
        let optionsBox = SettingsGroupBox(rows: [
            createSettingRow(
                title: l.enableHistory,
                description: l.enableHistoryDesc,
                control: {
                    let toggle = NSSwitch()
                    toggle.translatesAutoresizingMaskIntoConstraints = false
                    toggle.target = self
                    toggle.action = #selector(self.historyToggleChanged)
                    self.historyToggle = toggle
                    return toggle
                }()
            ),
            createSettingRow(
                title: l.launchAtStartup,
                description: l.launchAtStartupDesc,
                control: {
                    let toggle = NSSwitch()
                    toggle.translatesAutoresizingMaskIntoConstraints = false
                    toggle.target = self
                    toggle.action = #selector(self.launchOnLoginChanged)
                    self.launchOnLoginToggle = toggle
                    return toggle
                }()
            ),
            createSettingRow(
                title: l.muteDuringRecording,
                description: l.muteDuringRecordingDesc,
                control: {
                    let toggle = NSSwitch()
                    toggle.translatesAutoresizingMaskIntoConstraints = false
                    toggle.target = self
                    toggle.action = #selector(self.muteToggleChanged)
                    self.muteToggle = toggle
                    return toggle
                }()
            )
        ])
        mainStack.addArrangedSubview(optionsBox)
        optionsBox.widthAnchor.constraint(equalToConstant: 580).isActive = true
        
        // Reset Button
        let resetBtn = NSButton(title: l.reset, target: self, action: #selector(resetSettings))
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 13)
        
        let resetContainer = NSStackView(views: [resetBtn])
        resetContainer.translatesAutoresizingMaskIntoConstraints = false
        resetContainer.edgeInsets = NSEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        mainStack.addArrangedSubview(resetContainer)
        
        contentView.addSubview(mainStack)
        scrollView.documentView = contentView
        container.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        return container
    }
    
    private func createSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.alphaValue = 0.5
        return label
    }
    
    private func createSeparator() -> NSView {
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        separator.alphaValue = 0.3
        return separator
    }
    
    private func createMainTitle(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .labelColor
        return label
    }

    class SettingsGroupBox: NSView {
        init(rows: [NSView]) {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 10
            
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
                layer?.borderColor = NSColor(white: 1.0, alpha: 0.1).cgColor
            } else {
                layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.5).cgColor
                layer?.borderColor = NSColor(white: 0.0, alpha: 0.1).cgColor
            }
            layer?.borderWidth = 0.5
            
            let stack = NSStackView(views: rows)
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .vertical
            stack.spacing = 0
            stack.alignment = .leading
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
            
            // Add separators between rows
            if rows.count > 1 {
                for i in 0..<(rows.count - 1) {
                    let sep = NSBox()
                    sep.boxType = .separator
                    sep.alphaValue = 0.5
                    stack.insertArrangedSubview(sep, at: i * 2 + 1)
                }
            }
            
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        
        required init?(coder: NSCoder) { fatalError() }
    }
    
    class VocabularyRowView: NSTableCellView, NSTextFieldDelegate {
        var onDelete: (() -> Void)?
        var onEdit: (() -> Void)?
        var onSave: ((String, String) -> Void)?
        
        private let spokenLabel = NSTextField()
        private let correctedLabel = NSTextField()
        private let arrowIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)!)
        private let deleteBtn = NSButton()
        
        override init(frame: NSRect) {
            super.init(frame: frame)
            setupUI()
        }
        
        required init?(coder: NSCoder) { fatalError() }
        
        private func setupUI() {
            wantsLayer = true
            layer?.cornerRadius = 8
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
            } else {
                layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.5).cgColor
            }
            
            configureTextField(spokenLabel, isBold: false)
            configureTextField(correctedLabel, isBold: true)
            
            arrowIcon.translatesAutoresizingMaskIntoConstraints = false
            arrowIcon.contentTintColor = NSColor.tertiaryLabelColor
            
            deleteBtn.translatesAutoresizingMaskIntoConstraints = false
            deleteBtn.bezelStyle = .inline
            deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
            deleteBtn.contentTintColor = .secondaryLabelColor
            deleteBtn.target = self
            deleteBtn.action = #selector(deleteClicked)
            deleteBtn.isBordered = false
            
            addSubview(spokenLabel)
            addSubview(arrowIcon)
            addSubview(correctedLabel)
            addSubview(deleteBtn)
            
            NSLayoutConstraint.activate([
                spokenLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                spokenLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                
                arrowIcon.leadingAnchor.constraint(equalTo: spokenLabel.trailingAnchor, constant: 8),
                arrowIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
                arrowIcon.widthAnchor.constraint(equalToConstant: 20),
                
                correctedLabel.leadingAnchor.constraint(equalTo: arrowIcon.trailingAnchor, constant: 8),
                correctedLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                correctedLabel.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -8),
                
                // Equal width constraint to force both to be visible
                spokenLabel.widthAnchor.constraint(equalTo: correctedLabel.widthAnchor),
                
                deleteBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                deleteBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
                deleteBtn.widthAnchor.constraint(equalToConstant: 24),
                deleteBtn.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        
        private func configureTextField(_ textField: NSTextField, isBold: Bool) {
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: 13, weight: isBold ? .bold : .medium)
            textField.textColor = .labelColor
            textField.isEditable = true
            textField.isSelectable = true
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.delegate = self
            textField.focusRingType = .none
        }
        
        @objc private func deleteClicked() { onDelete?() }
        
        func configure(spoken: String, corrected: String) {
            spokenLabel.stringValue = spoken
            correctedLabel.stringValue = corrected
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            if obj.object is NSTextField {
                // Remove focus ring if any custom drawing was added
                layer?.backgroundColor = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1.0, alpha: 0.05).cgColor : NSColor(white: 1.0, alpha: 0.5).cgColor
                onSave?(spokenLabel.stringValue, correctedLabel.stringValue)
            }
        }
    }
    
    private func createSettingRow(title: String, description: String, control: NSView) -> NSView {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 12
        
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = .labelColor
        
        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        
        textStack.addArrangedSubview(titleLabel)
        if !description.isEmpty {
            textStack.addArrangedSubview(descLabel)
        }
        
        container.addArrangedSubview(textStack)
        container.addArrangedSubview(NSView()) // Spacer
        container.addArrangedSubview(control)
        
        // Special case for cardsStack or multi-line content
        if control.constraints.contains(where: { $0.constant == 160 && $0.firstAttribute == .height }) {
             NSLayoutConstraint.activate([
                container.heightAnchor.constraint(equalToConstant: 180)
            ])
        } else {
            NSLayoutConstraint.activate([
                container.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
        
        return container
    }
    
    private func createShortcutInfoRow(title: String, description: String, shortcut: String) -> NSView {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .horizontal
        container.alignment = .top
        container.spacing = 20
        
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        
        let descLabel = NSTextField(wrappingLabelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabelColor
        
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descLabel)
        
        // Simple label showing the fixed shortcut
        let shortcutLabel = NSTextField(labelWithString: shortcut)
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        shortcutLabel.alignment = .center
        shortcutLabel.wantsLayer = true
        shortcutLabel.layer?.cornerRadius = 6
        shortcutLabel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        container.addArrangedSubview(textStack)
        container.addArrangedSubview(shortcutLabel)
        
        NSLayoutConstraint.activate([
            textStack.widthAnchor.constraint(equalToConstant: 240),
            shortcutLabel.widthAnchor.constraint(equalToConstant: 120)
        ])
        
        return container
    }
    
    private func loadMicrophones() {
        microphonePopup.removeAllItems()
        
        let micStatus = PermissionsManager.shared.checkMicrophonePermission()
        let devices = AudioDeviceManager.shared.getInputDevices()
        let selectedDevice = AudioDeviceManager.shared.getSelectedDevice()
        let storedUID = UserDefaults.standard.string(forKey: Constants.Keys.selectedMicrophoneUID)
        
        // 1. Check if permission is denied
        if micStatus == .denied {
            microphonePopup.addItem(withTitle: "\(l.microphone) (\(l.micPermissionDenied))")
            microphonePopup.lastItem?.isEnabled = true
            microphonePopup.lastItem?.representedObject = "PERMISSION_DENIED"
        }
        
        // 2. Add available devices
        for device in devices {
            let nameLower = device.name.lowercased()
            if nameLower.contains("aggregate") || nameLower.contains("default") {
                continue
            }
            
            microphonePopup.addItem(withTitle: device.name)
            microphonePopup.lastItem?.representedObject = device
            
            if device.uid == selectedDevice?.uid {
                microphonePopup.select(microphonePopup.lastItem)
            }
        }
        
        // 3. Handle disconnected selected device
        if let uid = storedUID, !devices.contains(where: { $0.uid == uid }) {
            // Add it as disconnected at the top if it wasn't there
            let disconnectedTitle = "Unknown Device (\(l.micNotAvailable))"
            microphonePopup.insertItem(withTitle: disconnectedTitle, at: 0)
            microphonePopup.item(at: 0)?.isEnabled = false
            microphonePopup.selectItem(at: 0)
        }
        
        // 4. If nothing selected and we have devices, select first
        if microphonePopup.selectedItem == nil && microphonePopup.numberOfItems > 0 {
            microphonePopup.selectItem(at: 0)
        }
    }
    
    // MARK: - Model Section (Simplified for FluidAudio)
    
    @objc private func languageSelectionChanged(_ sender: NSPopUpButton) {
        if let langCode = sender.selectedItem?.representedObject as? String {
            ModelManager.shared.selectedLanguage = langCode
        }
    }
    
    
    private func createAIView() -> NSView {
    let container = NSView()
    
    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.autohidesScrollers = true
    
    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = containerView
    
    let mainStack = NSStackView()
    mainStack.translatesAutoresizingMaskIntoConstraints = false
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = 24
    mainStack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
    containerView.addSubview(mainStack)
    
    NSLayoutConstraint.activate([
        mainStack.topAnchor.constraint(equalTo: containerView.topAnchor),
        mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
        mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        mainStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        
        containerView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        containerView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        containerView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor)
    ])
    
    container.addSubview(scrollView)
    NSLayoutConstraint.activate([
        scrollView.topAnchor.constraint(equalTo: container.topAnchor),
        scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
    
    // 1. Header & Intro
    let headerStack = NSStackView()
    headerStack.orientation = .horizontal
    headerStack.distribution = .equalSpacing
    headerStack.translatesAutoresizingMaskIntoConstraints = false
    
    let title = createMainTitle(L10n.isFrench ? "Compétences IA" : "AI Skills")
    headerStack.addArrangedSubview(title)
    
    let addBtn = NSButton(title: "", target: self, action: #selector(addAISkill))
    addBtn.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Add Skill")
    addBtn.bezelStyle = .recessed
    addBtn.isBordered = false
    addBtn.contentTintColor = .controlAccentColor
    addBtn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    headerStack.addArrangedSubview(addBtn)
    
    mainStack.addArrangedSubview(headerStack)
    NSLayoutConstraint.activate([
        headerStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40)
    ])

    // 2. Coming Soon Placeholder
    let comingSoonContainer = NSStackView()
    comingSoonContainer.orientation = .vertical
    comingSoonContainer.alignment = .centerX
    comingSoonContainer.spacing = 20
    comingSoonContainer.translatesAutoresizingMaskIntoConstraints = false
    
    let icon = NSImageView(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) ?? NSImage())
    icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
    icon.contentTintColor = .tertiaryLabelColor
    
    let comingSoonTitle = NSTextField(labelWithString: L10n.isFrench ? "Bientôt disponible" : "Coming Soon")
    comingSoonTitle.font = NSFont.systemFont(ofSize: 20, weight: .bold)
    comingSoonTitle.textColor = .secondaryLabelColor
    
    let comingSoonDesc = NSTextField(wrappingLabelWithString: L10n.isFrench 
        ? "Les compétences IA sont en cours de développement et arriveront dans une prochaine mise à jour."
        : "AI Skills are currently under development and will arrive in a future update.")
    comingSoonDesc.font = NSFont.systemFont(ofSize: 14)
    comingSoonDesc.textColor = .tertiaryLabelColor
    comingSoonDesc.alignment = .center
    comingSoonDesc.preferredMaxLayoutWidth = 400
    
    comingSoonContainer.addArrangedSubview(icon)
    comingSoonContainer.addArrangedSubview(comingSoonTitle)
    comingSoonContainer.addArrangedSubview(comingSoonDesc)
    
    mainStack.addArrangedSubview(comingSoonContainer)
    
    // Center the coming soon view vertically in the remaining space
    mainStack.addArrangedSubview(NSView()) // Spacer to push content up if needed, or we can use distribution
    
    // We need to initialize the properties that were previously set here to avoid nil crashes if accessed elsewhere
    // Although with the UI hidden, they shouldn't be interacted with.
    // However, let's minimally init them to be safe.
    self.llmProviderPopup = NSPopUpButton()
    self.apiKeyField = NSTextField()
    self.cloudModelLabel = NSTextField()
    self.statusIndicator = NSImageView()
    self.apiKeyStack = NSStackView()
    self.localModelLabel = NSTextField()
    self.downloadProgressBar = NSProgressIndicator()
    self.downloadProgressLabel = NSTextField()
    self.aiModesStack = NSStackView()
    
    NSLayoutConstraint.activate([
        comingSoonContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        comingSoonContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
    ])
    
    setupLLMObservers()
    
    return container
    }
    
    @objc private func toggleLocalAI(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        SettingsManager.shared.llmEnabled = enabled
        
        if enabled {
            // Trigger download if needed
            Task {
                if !LLMManager.shared.isReady {
                   try? await LLMManager.shared.initialize()
                }
            }
        }
    }
    
    private func setupLLMObservers() {
        // Cancel existing subscriptions
        cancellables.removeAll()
        
        LLMManager.shared.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.updateDownloadProgress(progress)
            }
            .store(in: &cancellables)
            
        LLMManager.shared.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.downloadProgressBar?.isHidden = !isLoading
                self?.downloadProgressLabel?.isHidden = !isLoading
                self?.localAIToggle?.isEnabled = !isLoading
                if isLoading {
                    self?.downloadProgressBar?.startAnimation(nil)
                } else {
                    self?.downloadProgressBar?.stopAnimation(nil)
                }
            }
            .store(in: &cancellables)
            
        // Initial state check
        if LLMManager.shared.isLoading {
            downloadProgressBar?.startAnimation(nil)
            downloadProgressBar?.isHidden = false
            downloadProgressLabel?.isHidden = false
            localAIToggle?.isEnabled = false
        }
    }
    
    private func updateDownloadProgress(_ progress: Double) {
        guard let bar = downloadProgressBar, let label = downloadProgressLabel else { return }
        
        let percent = Int(progress * 100)
        let totalMB = Constants.modelSizeMB
        let currentMB = Int(progress * totalMB)
        
        bar.doubleValue = progress * 100
        label.stringValue = "\(percent)% (\(currentMB) MB / \(Int(totalMB)) MB)"
        
        if progress >= 1.0 {
            label.stringValue = L10n.isFrench ? "Téléchargement terminé" : "Download complete"
             DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                bar.isHidden = true
                label.isHidden = true
                self.localAIToggle?.isEnabled = true
             }
        }
    }

    @objc private func addAISkill() {
        let newSkill = AISkill(name: "Nouvelle Compétence", trigger: "mon trigger", prompt: "Mes instructions...", color: "blue")
        var skills = SettingsManager.shared.aiSkills
        skills.append(newSkill)
        SettingsManager.shared.aiSkills = skills
        refreshAISkillsList()
    }

    private func refreshAISkillsList() {
        aiModesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let skills = SettingsManager.shared.aiSkills
        for (index, skill) in skills.enumerated() {
            let row = AISkillRowView(skill: skill, index: index)
            row.onDelete = { [weak self] idx in
                var currentSkills = SettingsManager.shared.aiSkills
                if idx < currentSkills.count {
                    currentSkills.remove(at: idx)
                    SettingsManager.shared.aiSkills = currentSkills
                    self?.refreshAISkillsList()
                }
            }
            row.onUpdate = { idx, updatedSkill in
                var currentSkills = SettingsManager.shared.aiSkills
                if idx < currentSkills.count {
                    currentSkills[idx] = updatedSkill
                    SettingsManager.shared.aiSkills = currentSkills
                }
            }
            aiModesStack.addArrangedSubview(row)
        }
    }


private func createHistoryView() -> NSView {
        let container = NSView()
        
        let mainStack = NSStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 24
        mainStack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        
        let title = createMainTitle(l.historyTab)
        mainStack.addArrangedSubview(title)
        mainStack.setCustomSpacing(15, after: title)
        
        container.addSubview(mainStack)
        
        // Scroll view for history cards
        historyScrollView = NSScrollView()
        historyScrollView.translatesAutoresizingMaskIntoConstraints = false
        historyScrollView.hasVerticalScroller = true
        historyScrollView.autohidesScrollers = true
        historyScrollView.borderType = .noBorder
        historyScrollView.drawsBackground = false
        
        historyTableView = NSTableView()
        historyTableView.delegate = self
        historyTableView.dataSource = self
        historyTableView.backgroundColor = .clear
        historyTableView.usesAlternatingRowBackgroundColors = false
        historyTableView.rowHeight = 80
        historyTableView.intercellSpacing = NSSize(width: 0, height: 12)
        historyTableView.gridStyleMask = []
        historyTableView.headerView = nil
        historyTableView.selectionHighlightStyle = .none
        
        let mainColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        mainColumn.resizingMask = .autoresizingMask
        historyTableView.addTableColumn(mainColumn)
        
        historyScrollView.documentView = historyTableView
        mainStack.addArrangedSubview(historyScrollView)
        
        // Buttons container
        let buttonStack = NSStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 15
        
        let clearButton = NSButton(title: l.clearHistory, target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .rounded
        clearButton.font = NSFont.systemFont(ofSize: 13)
        
        let copyButton = NSButton(title: l.copy, target: self, action: #selector(copySelected))
        copyButton.bezelStyle = .rounded
        copyButton.font = NSFont.systemFont(ofSize: 13)
        
        buttonStack.addArrangedSubview(clearButton)
        buttonStack.addArrangedSubview(copyButton)
        
        mainStack.addArrangedSubview(buttonStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: container.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            historyScrollView.widthAnchor.constraint(equalToConstant: 580),
            buttonStack.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        return container
    }
    
    private func createVocabularyView() -> NSView {
        let container = NSView()
        
        let mainStack = NSStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 24
        mainStack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        
        // Header
        let headerTitle = createMainTitle(l.vocabularyTab)
        mainStack.addArrangedSubview(headerTitle)
        mainStack.setCustomSpacing(10, after: headerTitle)
        
        let desc = NSTextField(wrappingLabelWithString: l.vocabularyDesc)
        desc.font = NSFont.systemFont(ofSize: 13)
        desc.textColor = .secondaryLabelColor
        desc.preferredMaxLayoutWidth = 550
        mainStack.addArrangedSubview(desc)
        
        // Add Button
        let addBtn = NSButton(title: l.addWord, target: self, action: #selector(addVocabularyEntry))
        addBtn.bezelStyle = .rounded
        addBtn.controlSize = .large
        addBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        
        // Table Container (Liquid Glass)
        let tableScroll = NSScrollView()
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.drawsBackground = false
        tableScroll.borderType = .noBorder
        
        vocabularyTableView = NSTableView()
        vocabularyTableView.delegate = self
        vocabularyTableView.dataSource = self
        vocabularyTableView.headerView = nil
        vocabularyTableView.backgroundColor = .clear
        vocabularyTableView.intercellSpacing = NSSize(width: 0, height: 10)
        vocabularyTableView.style = .plain
        vocabularyTableView.selectionHighlightStyle = .none
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main"))
        col.width = 500
        vocabularyTableView.addTableColumn(col)
        
        tableScroll.documentView = vocabularyTableView
        
        let tableContainer = NSView()
        tableContainer.translatesAutoresizingMaskIntoConstraints = false
        tableContainer.wantsLayer = true
        tableContainer.layer?.cornerRadius = 10
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tableContainer.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
            tableContainer.layer?.borderColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        } else {
            tableContainer.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.5).cgColor
            tableContainer.layer?.borderColor = NSColor(white: 0.0, alpha: 0.1).cgColor
        }
        tableContainer.layer?.borderWidth = 0.5
        
        tableContainer.addSubview(tableScroll)
        
        // Empty State
        let emptyState = NSTextField(labelWithString: "No vocabulary added")
        emptyState.textColor = .tertiaryLabelColor
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.isHidden = true // Todo: bind to data count
        tableContainer.addSubview(emptyState)
        
        mainStack.addArrangedSubview(addBtn)
        mainStack.addArrangedSubview(tableContainer)
        
        container.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: container.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            tableScroll.topAnchor.constraint(equalTo: tableContainer.topAnchor, constant: 10),
            tableScroll.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor, constant: 10),
            tableScroll.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor, constant: -10),
            tableScroll.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor, constant: -10),
            
            emptyState.centerXAnchor.constraint(equalTo: tableContainer.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: tableContainer.centerYAnchor),
            
            tableContainer.heightAnchor.constraint(equalToConstant: 350),
            tableContainer.widthAnchor.constraint(equalToConstant: 580)
        ])
        
        return container
    }
    
    @objc private func addVocabularyEntry() {
        vocabularyData.append((spoken: "supra sonic", corrected: "SupraSonic"))
        vocabularyTableView.reloadData()
        saveVocabulary()
        
        // Select and edit the new row
        let lastRow = vocabularyData.count - 1
        vocabularyTableView.selectRowIndexes(IndexSet(integer: lastRow), byExtendingSelection: false)
        vocabularyTableView.editColumn(0, row: lastRow, with: nil, select: true)
    }
    
    @objc private func deleteVocabularyEntry() {
        let row = vocabularyTableView.selectedRow
        guard row >= 0 && row < vocabularyData.count else { return }
        
        vocabularyData.remove(at: row)
        vocabularyTableView.reloadData()
        saveVocabulary()
    }
    
    private func saveVocabulary() {
        var mapping: [String: String] = [:]
        for entry in vocabularyData {
            if !entry.spoken.isEmpty {
                mapping[entry.spoken] = entry.corrected
            }
        }
        SettingsManager.shared.vocabularyMapping = mapping
    }
    
    private func loadVocabulary() {
        let mapping = SettingsManager.shared.vocabularyMapping
        if mapping.isEmpty {
            // First run default
            vocabularyData = [(spoken: "supra sonic", corrected: "SupraSonic")]
            saveVocabulary()
        } else {
            vocabularyData = mapping.map { (spoken: $0.key, corrected: $0.value) }
                .sorted { $0.spoken < $1.spoken }
        }
        vocabularyTableView?.reloadData()
    }
    
    private func loadSettings() {
        let settings = SettingsManager.shared
        
        // Load toggles
        historyToggle.state = settings.historyEnabled ? .on : .off
        launchOnLoginToggle.state = settings.launchOnLogin ? .on : .off
        muteToggle.state = settings.muteSystemSoundDuringRecording ? .on : .off
        
        // Load hotkey mode
        updateModeCards(settings.hotkeyMode)
        
        // Load hotkey button
        hotkeyButton.setHotkey(keyCode: settings.pushToTalkKey, 
                               modifiers: settings.pushToTalkModifiers,
                               keyString: settings.pushToTalkKeyString)
        
        // Load microphones and history
        loadMicrophones()
        reloadHistory()
        loadVocabulary()
        
        // Load AI settings
        refreshAISkillsList()
        
        // Load LLM Provider
        let currentProvider = settings.llmProvider
        if let index = SettingsManager.LLMProvider.allCases.firstIndex(of: currentProvider) {
            llmProviderPopup.selectItem(at: index)
        }
        
        updateApiKeyVisibility(for: currentProvider)
        
        switch currentProvider {
        case .google: 
            apiKeyField.stringValue = settings.geminiApiKey
            cloudModelLabel.stringValue = "Model: \(Constants.geminiModelName)"
        case .openai: 
            apiKeyField.stringValue = settings.openaiApiKey
            cloudModelLabel.stringValue = "Model: \(Constants.openaiModelName)"
        case .anthropic: 
            apiKeyField.stringValue = settings.anthropicApiKey
            cloudModelLabel.stringValue = "Model: \(Constants.anthropicModelName)"
        case .local: 
            apiKeyField.stringValue = ""
            cloudModelLabel.stringValue = ""
        case .none:
            apiKeyField.stringValue = ""
            cloudModelLabel.stringValue = ""
        }
        
        // Ensure UI is updated
        updateApiKeyVisibility(for: currentProvider)
        validateCurrentKey()
    }
    
    @objc private func llmProviderChanged(_ sender: NSPopUpButton) {
        guard let provider = sender.selectedItem?.representedObject as? SettingsManager.LLMProvider else { return }
        SettingsManager.shared.llmProvider = provider
        updateApiKeyVisibility(for: provider)
        
        // Unload local model to free RAM if switching to cloud
        if provider != .local {
            LLMManager.shared.unload()
            
            // Immediately reload Parakeet so it stays in RAM even after MLX cache clear
            Task {
                try? await TranscriptionManager.shared.initialize(forceReload: true)
            }
        }
        
        // Load existing key and update model info
        switch provider {
        case .google:
            apiKeyField.stringValue = SettingsManager.shared.geminiApiKey
            cloudModelLabel.stringValue = "Model: \(Constants.geminiModelName)"
        case .openai:
            apiKeyField.stringValue = SettingsManager.shared.openaiApiKey
            cloudModelLabel.stringValue = "Model: \(Constants.openaiModelName)"
        case .anthropic:
            apiKeyField.stringValue = SettingsManager.shared.anthropicApiKey
            cloudModelLabel.stringValue = "Model: \(Constants.anthropicModelName)"
        case .local:
            apiKeyField.stringValue = ""
            cloudModelLabel.stringValue = ""
        case .none:
            apiKeyField.stringValue = ""
            cloudModelLabel.stringValue = ""
        }
        
        // Trigger validation if key is not empty
        validateCurrentKey()
    }
    
    @objc private func validateCurrentKey() {
        let provider = SettingsManager.shared.llmProvider
        let key = apiKeyField.stringValue
        
        guard provider != .local else {
            statusIndicator.contentTintColor = .clear
            return
        }
        
        if key.isEmpty {
            statusIndicator.contentTintColor = .secondaryLabelColor
            statusIndicator.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Empty")
            return
        }
        
        // Show progress state
        statusIndicator.contentTintColor = .systemOrange
        statusIndicator.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Validating...")
        
        Task {
            do {
                let isValid = try await LLMManager.shared.validateApiKey(provider: provider, apiKey: key)
                DispatchQueue.main.async { [weak self] in
                    if isValid {
                        self?.statusIndicator.contentTintColor = .systemGreen
                        self?.statusIndicator.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Valid")
                    } else {
                        self?.statusIndicator.contentTintColor = .systemRed
                        self?.statusIndicator.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Invalid")
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    print("❌ Validation failed: \(error.localizedDescription)")
                    self?.statusIndicator.contentTintColor = .systemRed
                    self?.statusIndicator.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Error")
                }
            }
        }
    }
    
    private func updateApiKeyVisibility(for provider: SettingsManager.LLMProvider) {
        let isLocal = (provider == .local)
        apiKeyStack.isHidden = isLocal
        localModelLabel.isHidden = !isLocal
    }
    
    private func updateModeCards(_ mode: SettingsManager.HotkeyMode) {
        pttCard.isSelected = (mode == .pushToTalk)
        toggleCard.isSelected = (mode == .toggle)
    }
    
    @objc private func hotkeyModeCardSelected(_ sender: ModeCardView) {
        let mode = sender.mode
        SettingsManager.shared.hotkeyMode = mode
        updateModeCards(mode)
        NotificationCenter.default.post(name: Constants.NotificationNames.hotkeySettingsChanged, object: nil)
    }
    
    @objc private func hotkeyChanged(_ sender: HotkeyButton) {
        SettingsManager.shared.pushToTalkKey = sender.keyCode
        SettingsManager.shared.pushToTalkModifiers = sender.modifiers
        SettingsManager.shared.pushToTalkKeyString = sender.keyString
        NotificationCenter.default.post(name: Constants.NotificationNames.hotkeySettingsChanged, object: nil)
    }
    
    func reloadHistory() {
        historyData = SettingsManager.shared.transcriptionHistory
        historyTableView?.reloadData()
    }
    
    @objc private func microphoneChanged() {
        let micStatus = PermissionsManager.shared.checkMicrophonePermission()
        
        if micStatus == .denied {
            PermissionsManager.shared.openMicrophoneSettings()
            loadMicrophones() // Refresh to show current state
            return
        }
        
        if micStatus == .notDetermined {
            PermissionsManager.shared.requestMicrophonePermission { [weak self] granted in
                self?.loadMicrophones()
            }
            return
        }
        
        if let device = microphonePopup.selectedItem?.representedObject as? AudioDeviceManager.AudioDevice {
            AudioDeviceManager.shared.setInputDevice(device)
        }
    }
    
    @objc private func historyToggleChanged() {
        SettingsManager.shared.historyEnabled = historyToggle.state == .on
    }
    
    @objc private func launchOnLoginChanged() {
        SettingsManager.shared.launchOnLogin = launchOnLoginToggle.state == .on
    }
    
    @objc private func muteToggleChanged() {
        SettingsManager.shared.muteSystemSoundDuringRecording = muteToggle.state == .on
    }
    
    @objc private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = l.resetConfirm
        alert.informativeText = l.resetMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: l.reset)
        alert.addButton(withTitle: l.cancel)
        
        if alert.runModal() == .alertFirstButtonReturn {
            SettingsManager.shared.resetToDefaults()
            loadSettings()
            loadMicrophones()
            NotificationCenter.default.post(name: Constants.NotificationNames.hotkeySettingsChanged, object: nil)
        }
    }
    
    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = l.clearHistoryConfirm
        alert.informativeText = l.clearHistoryMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: l.clearHistory)
        alert.addButton(withTitle: l.cancel)
        
        if alert.runModal() == .alertFirstButtonReturn {
            SettingsManager.shared.clearHistory()
            reloadHistory()
        }
    }
    
    @objc private func copySelected() {
        let row = historyTableView.selectedRow
        guard row >= 0, row < historyData.count else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(historyData[row].text, forType: .string)
    }
    
    func show() {
        reloadHistory()
        loadMicrophones()
        
        self.center()
        self.level = .floating
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure it stays on top for a moment to catch attention
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.level = .normal
        }
    }
    
    func addHistoryEntry(_ entry: TranscriptionEntry) {
        historyData.insert(entry, at: 0)
        historyTableView?.reloadData()
    }
}

// MARK: - NSTableViewDelegate & DataSource

extension SettingsWindow: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == vocabularyTableView {
            // Update EmptyState visibility if it exists (simplification)
            return vocabularyData.count
        }
        return historyData.count
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView == vocabularyTableView {
            return 44 // Liquid Glass row height
        }
        guard row < historyData.count else { return 80 }
        let text = historyData[row].text
        let baseHeight: CGFloat = 80
        let charsPerLine = 70
        let lines = max(1, (text.count / charsPerLine) + 1)
        return max(baseHeight, CGFloat(lines) * 20 + 50)
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == vocabularyTableView {
            guard row < vocabularyData.count else { return nil }
            let item = vocabularyData[row]
            
            let id = NSUserInterfaceItemIdentifier("VocabRow")
            let view = tableView.makeView(withIdentifier: id, owner: self) as? VocabularyRowView ?? VocabularyRowView()
            view.identifier = id
            view.configure(spoken: item.spoken, corrected: item.corrected)
            
            view.onDelete = { [weak self] in
                self?.vocabularyData.remove(at: row)
                self?.vocabularyTableView.reloadData()
                self?.saveVocabulary()
            }
            
            view.onSave = { [weak self] newSpoken, newCorrected in
                guard let self = self else { return }
                guard row < self.vocabularyData.count else { return }
                
                self.vocabularyData[row] = (spoken: newSpoken, corrected: newCorrected)
                self.saveVocabulary()
                // No need to reload data if we are just editing in place
            }
            
            return view
        }
        
        guard row < historyData.count else { return nil }
        let entry = historyData[row]
        
        let cellIdentifier = NSUserInterfaceItemIdentifier("historyCard")
        let cardView: NSView
        
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) {
            cardView = existing
        } else {
            cardView = NSView()
            cardView.identifier = cellIdentifier
            cardView.wantsLayer = true
            cardView.layer?.cornerRadius = 12
            cardView.layer?.borderWidth = 1
            
            let stack = NSStackView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
            
            let dateLabel = NSTextField(labelWithString: "")
            dateLabel.identifier = NSUserInterfaceItemIdentifier("date")
            dateLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            dateLabel.textColor = .secondaryLabelColor
            
            let textField = NSTextField(wrappingLabelWithString: "")
            textField.identifier = NSUserInterfaceItemIdentifier("text")
            textField.font = NSFont.systemFont(ofSize: 13)
            textField.textColor = .labelColor
            textField.isEditable = false
            textField.isSelectable = true
            textField.maximumNumberOfLines = 0
            
            stack.addArrangedSubview(dateLabel)
            stack.addArrangedSubview(textField)
            cardView.addSubview(stack)
            
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cardView.topAnchor),
                stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
            ])
        }
        
        // Update content
        if let stack = cardView.subviews.first as? NSStackView {
            let dateLabel = stack.arrangedSubviews.first { $0.identifier?.rawValue == "date" } as? NSTextField
            let textField = stack.arrangedSubviews.first { $0.identifier?.rawValue == "text" } as? NSTextField
            
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            dateLabel?.stringValue = formatter.string(from: entry.date)
            textField?.stringValue = entry.text
        }
        
        // Update styling
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            cardView.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
            cardView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        } else {
            cardView.layer?.backgroundColor = NSColor.white.cgColor
            cardView.layer?.borderColor = NSColor(white: 0.0, alpha: 0.1).cgColor
        }
        
        return cardView
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        historyTableView.reloadData()
    }
}

// MARK: - Hotkey Button

class HotkeyButton: NSButton {
    var keyCode: UInt16 = 0
    var modifiers: UInt = 0
    var keyString: String = ""
    private var isRecording = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.bezelStyle = .rounded
        self.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        self.title = L10n.current.clickToSet
        self.wantsLayer = true
        self.layer?.cornerRadius = 10
        self.setButtonType(.momentaryPushIn)
        updateStyling()
    }
    
    private func updateStyling() {
        if isRecording {
            self.contentTintColor = .white
            self.layer?.backgroundColor = NSColor.systemRed.cgColor
        } else {
            self.contentTintColor = .labelColor
            self.layer?.backgroundColor = NSColor.controlTextColor.withAlphaComponent(0.05).cgColor
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setHotkey(keyCode: UInt16, modifiers: UInt, keyString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyString = keyString
        updateTitle()
    }
    
    private func updateTitle() {
        if isRecording {
            self.title = L10n.current.pressKey
            return
        }
        
        if keyCode == 0 {
            self.title = L10n.current.clickToSet
            return
        }

        var parts: [String] = []
        
        // 1. Modifiers (only show generic symbols if the key itself is not a modifier)
        let isModifierOnlyKey = isModifierKeyCode(keyCode)
        if !isModifierOnlyKey {
            if modifiers & UInt(1 << 17) != 0 { parts.append("⇧") }
            if modifiers & UInt(1 << 18) != 0 { parts.append("⌃") }
            if modifiers & UInt(1 << 19) != 0 { parts.append("⌥") }
            if modifiers & UInt(1 << 20) != 0 { parts.append("⌘") }
        }
        
        // 2. Key
        if isModifierOnlyKey {
            // For modifier-only keys, show the specific side (Left/Right)
            let modName = modifierKeyCodeToString(keyCode)
            parts.append(modName)
        } else {
            // For regular keys, add a space if there are modifiers
            if !parts.isEmpty {
                parts.append(" " + keyString)
            } else {
                parts.append(keyString)
            }
        }
        
        self.title = parts.isEmpty ? L10n.current.clickToSet : parts.joined()
    }
    
    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        return Constants.KeyCodes.modifiers.contains(keyCode)
    }
    
    private func modifierKeyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case Constants.KeyCodes.commandRight: return "⌘ " + (L10n.isFrench ? "Droite" : "Right")
        case Constants.KeyCodes.commandLeft: return "⌘ " + (L10n.isFrench ? "Gauche" : "Left")
        case Constants.KeyCodes.shiftLeft: return "⇧ " + (L10n.isFrench ? "Gauche" : "Left")
        case Constants.KeyCodes.shiftRight: return "⇧ " + (L10n.isFrench ? "Droite" : "Right")
        case Constants.KeyCodes.optionLeft: return "⌥ " + (L10n.isFrench ? "Gauche" : "Left")
        case Constants.KeyCodes.optionRight: return "⌥ " + (L10n.isFrench ? "Droite" : "Right")
        case Constants.KeyCodes.controlLeft: return "⌃ " + (L10n.isFrench ? "Gauche" : "Left")
        case Constants.KeyCodes.controlRight: return "⌃ " + (L10n.isFrench ? "Droite" : "Right")
        default: return ""
        }
    }


    
    override func mouseDown(with event: NSEvent) {
        if isRecording {
            cancelRecording()
        } else {
            startRecording()
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    private func startRecording() {
        isRecording = true
        self.title = L10n.current.pressKey
        updateStyling()
        self.needsDisplay = true
        
        // Make window key and this button first responder
        self.window?.makeKeyAndOrderFront(nil)
        self.window?.makeFirstResponder(self)
        
        // Add BOTH local and global monitors to ensure we catch all events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return }
            _ = self.handleKeyEvent(event)
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            // Escape cancels
            if event.keyCode == Constants.KeyCodes.escape {
                cancelRecording()
                return true
            }
            self.keyCode = event.keyCode
            self.modifiers = event.modifierFlags.rawValue & 0x1F0000
            self.keyString = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            finishRecording()
            return true
        } else if event.type == .flagsChanged {
            let modifierKeyCode = event.keyCode
            // Check if this is a modifier key press (not release)
            if isModifierKeyCode(modifierKeyCode) {
                // Check if the key is being pressed (modifier flag is set)
                let isPressed = isModifierPressed(event: event, keyCode: modifierKeyCode)
                if isPressed {
                    self.keyCode = modifierKeyCode
                    self.modifiers = event.modifierFlags.rawValue & 0x1F0000
                    finishRecording()
                    return true
                }
            }
        }
        return false
    }
    
    private func isModifierPressed(event: NSEvent, keyCode: UInt16) -> Bool {
        switch keyCode {
        case Constants.KeyCodes.commandRight, Constants.KeyCodes.commandLeft: return event.modifierFlags.contains(.command)
        case Constants.KeyCodes.shiftLeft, Constants.KeyCodes.shiftRight: return event.modifierFlags.contains(.shift)
        case Constants.KeyCodes.optionLeft, Constants.KeyCodes.optionRight: return event.modifierFlags.contains(.option)
        case Constants.KeyCodes.controlLeft, Constants.KeyCodes.controlRight: return event.modifierFlags.contains(.control)
        default: return false
        }
    }
    
    private func finishRecording() {
        removeMonitors()
        isRecording = false
        updateTitle()
        updateStyling()
        
        // Notify the target that the hotkey changed
        DispatchQueue.main.async {
            self.sendAction(self.action, to: self.target)
        }
    }
    
    private func cancelRecording() {
        removeMonitors()
        isRecording = false
        updateTitle()
        updateStyling()
    }
    
    private func removeMonitors() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
    
    deinit {
        removeMonitors()
    }
}

// MARK: - ModeCardView

// MARK: - Sidebar Components

class SidebarView: NSView {
    var onSectionSelected: ((SettingsWindow.SettingsSection) -> Void)?
    private var itemViews: [SidebarItem] = []
    private var stack: NSStackView!
    
    init() {
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 20, right: 12)
        
        let searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = L10n.isFrench ? "Rechercher" : "Search"
        searchField.bezelStyle = .roundedBezel
        searchField.controlSize = .large
        
        let searchContainer = NSStackView(views: [searchField])
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.edgeInsets = NSEdgeInsets(top: 24, left: 16, bottom: 10, right: 16)
        
        addSubview(searchContainer)
        addSubview(stack)
        
        for section in SettingsWindow.SettingsSection.allCases {
            let item = SidebarItem(section: section)
            item.onClick = { [weak self] in
                self?.onSectionSelected?(section)
            }
            stack.addArrangedSubview(item)
            itemViews.append(item)
            
            NSLayoutConstraint.activate([
                item.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                item.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
                item.heightAnchor.constraint(equalToConstant: 34)
            ])
        }
        
        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: topAnchor),
            searchContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            stack.topAnchor.constraint(equalTo: searchContainer.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    func selectSection(_ section: SettingsWindow.SettingsSection) {
        for (index, item) in itemViews.enumerated() {
            item.isSelected = (index == section.rawValue)
        }
    }
}

class SidebarItem: NSView {
    let section: SettingsWindow.SettingsSection
    var onClick: (() -> Void)?
    
    private let iconView: NSImageView
    private let iconBg: NSView
    private let titleLabel: NSTextField
    private let selectionView: NSView
    
    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    
    init(section: SettingsWindow.SettingsSection) {
        self.section = section
        
        iconBg = NSView()
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.wantsLayer = true
        iconBg.layer?.cornerRadius = 6
        
        // Define Sequoia-style colors
        switch section {
        case .config: iconBg.layer?.backgroundColor = NSColor.systemBlue.cgColor
        case .history: iconBg.layer?.backgroundColor = NSColor.systemOrange.cgColor
        case .ai: iconBg.layer?.backgroundColor = NSColor.systemPurple.cgColor
        case .vocabulary: iconBg.layer?.backgroundColor = NSColor.systemGreen.cgColor
        }
        
        iconView = NSImageView(image: NSImage(systemSymbolName: section.iconName, accessibilityDescription: nil) ?? NSImage())
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        iconView.contentTintColor = .white
        
        titleLabel = NSTextField(labelWithString: section.title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = .labelColor
        
        selectionView = NSView()
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 8
        selectionView.alphaValue = 0
        
        super.init(frame: .zero)
        
        addSubview(selectionView)
        addSubview(iconBg)
        iconBg.addSubview(iconView)
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            selectionView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            selectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            selectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            selectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            
            iconBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 24),
            iconBg.heightAnchor.constraint(equalToConstant: 24),
            
            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        updateAppearance()
        
        // Add tracking area for hover
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateAppearance() {
        if isSelected {
            selectionView.alphaValue = 1
            selectionView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            titleLabel.textColor = .white
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        } else {
            selectionView.alphaValue = 0
            titleLabel.textColor = .labelColor
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                selectionView.animator().alphaValue = 0.1
                selectionView.layer?.backgroundColor = NSColor.labelColor.cgColor
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                selectionView.animator().alphaValue = 0
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - ModeCardView

class ModeCardView: NSControl {
    let mode: SettingsManager.HotkeyMode
    private let titleLabel: NSTextField
    private let descLabel: NSTextField
    private let iconView: NSImageView
    private let bgView: NSView
    
    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    
    init(title: String, description: String, iconName: String, mode: SettingsManager.HotkeyMode) {
        self.mode = mode
        self.titleLabel = NSTextField(labelWithString: title)
        self.titleLabel.isSelectable = false
        self.descLabel = NSTextField(wrappingLabelWithString: description)
        self.descLabel.isSelectable = false
        self.iconView = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil) ?? NSImage())
        self.bgView = NSView()
        
        super.init(frame: .zero)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        bgView.translatesAutoresizingMaskIntoConstraints = false
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 16
        bgView.layer?.borderWidth = 1.5
        addSubview(bgView)
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        
        let stack = NSStackView(views: [iconView, titleLabel, descLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            bgView.topAnchor.constraint(equalTo: topAnchor),
            bgView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bgView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bgView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconView.heightAnchor.constraint(equalToConstant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 28)
        ])
        
        updateAppearance()
    }
    
    private func updateAppearance() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            if isSelected {
                bgView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
                bgView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
                iconView.contentTintColor = .controlAccentColor
                titleLabel.textColor = .labelColor
            } else {
                bgView.layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.02).cgColor
                bgView.layer?.borderColor = NSColor.textColor.withAlphaComponent(0.05).cgColor
                iconView.contentTintColor = .secondaryLabelColor
                titleLabel.textColor = .secondaryLabelColor
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if let target = target, let action = action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

extension String {
    func height(withConstrainedWidth width: CGFloat, font: NSFont) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font: font], context: nil)
        return ceil(boundingBox.height)
    }
}

extension SettingsWindow: NSTextViewDelegate {
}

extension SettingsWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        if textField == apiKeyField {
            let provider = SettingsManager.shared.llmProvider
            let value = textField.stringValue
            
            // Save immediately
            switch provider {
            case .google: SettingsManager.shared.geminiApiKey = value
            case .openai: SettingsManager.shared.openaiApiKey = value
            case .anthropic: SettingsManager.shared.anthropicApiKey = value
            case .local, .none: break
            }
            
            // Validate after a small delay (debounce)
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(validateCurrentKey), object: nil)
            self.perform(#selector(validateCurrentKey), with: nil, afterDelay: 1.0)
        }
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              textField.identifier?.rawValue == "VocabCell" else { return }
        
        let row = vocabularyTableView.row(for: textField)
        let col = vocabularyTableView.column(for: textField)
        
        guard row >= 0 && row < vocabularyData.count else { return }
        
        if col == 0 { // Spoken
            vocabularyData[row].spoken = textField.stringValue
        } else if col == 1 { // Corrected
            vocabularyData[row].corrected = textField.stringValue
        }
        
        saveVocabulary()
    }
}

// MARK: - AI Skill Row View
class AISkillRowView: NSView, NSTextFieldDelegate, NSTextViewDelegate {
    var skill: AISkill
    var index: Int
    var onDelete: ((Int) -> Void)?
    var onUpdate: ((Int, AISkill) -> Void)?
    
    private var isExpanded: Bool = false
    private var headerRow: NSStackView!
    private var promptContainer: NSView!
    private var chevronBtn: NSButton!
    private var nameLabel: NSTextField!
    private var triggerLabel: NSTextField!
    private var colorIndicator: NSView!
    
    // Editable fields (in expanded section)
    private var nameField: NSTextField!
    private var triggerField: NSTextField!
    private var promptTextView: NSTextView!
    private var colorPopup: NSPopUpButton!
    
    private var trackingArea: NSTrackingArea?
    
    let colors: [String: NSColor] = [
        "blue": .systemBlue,
        "purple": .systemPurple,
        "orange": .systemOrange,
        "green": .systemGreen,
        "red": .systemRed,
        "gray": .systemGray
    ]
    
    init(skill: AISkill, index: Int) {
        self.skill = skill
        self.index = index
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.1).cgColor
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        
        // 1. Header Row (Always Visible)
        headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12
        headerRow.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 12)
        
        chevronBtn = NSButton(title: "", target: self, action: #selector(toggleExpand))
        chevronBtn.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Expand")
        chevronBtn.isBordered = false
        chevronBtn.bezelStyle = .recessed
        chevronBtn.contentTintColor = .secondaryLabelColor
        chevronBtn.target = self
        chevronBtn.action = #selector(toggleExpand)
        
        colorIndicator = NSView()
        colorIndicator.translatesAutoresizingMaskIntoConstraints = false
        colorIndicator.wantsLayer = true
        colorIndicator.layer?.cornerRadius = 6
        colorIndicator.layer?.backgroundColor = colors[skill.color]?.cgColor ?? NSColor.systemBlue.cgColor
        
        nameLabel = NSTextField(labelWithString: skill.name)
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = .labelColor
        
        let plusLabel = NSTextField(labelWithString: "+")
        plusLabel.font = NSFont.systemFont(ofSize: 14, weight: .light)
        plusLabel.textColor = .tertiaryLabelColor
        
        triggerLabel = NSTextField(labelWithString: skill.trigger)
        triggerLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        triggerLabel.textColor = .controlAccentColor
        
        let deleteBtn = NSButton(title: "", target: self, action: #selector(deleteSelf))
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteBtn.isBordered = false
        deleteBtn.bezelStyle = .recessed
        deleteBtn.contentTintColor = .systemRed.withAlphaComponent(0.6)
        
        headerRow.addArrangedSubview(chevronBtn)
        headerRow.addArrangedSubview(colorIndicator)
        headerRow.addArrangedSubview(nameLabel)
        headerRow.addArrangedSubview(plusLabel)
        headerRow.addArrangedSubview(triggerLabel)
        headerRow.addArrangedSubview(NSView()) // Spacer
        headerRow.addArrangedSubview(deleteBtn)
        
        NSLayoutConstraint.activate([
            colorIndicator.widthAnchor.constraint(equalToConstant: 12),
            colorIndicator.heightAnchor.constraint(equalToConstant: 12)
        ])
        
        mainStack.addArrangedSubview(headerRow)
        
        // 2. Details Section (Hidden by default)
        promptContainer = NSView()
        promptContainer.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.isHidden = true
        
        let detailStack = NSStackView()
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 16
        detailStack.edgeInsets = NSEdgeInsets(top: 0, left: 44, bottom: 20, right: 16)
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Editable Name, Trigger & Color
        let topFieldsRow = NSStackView()
        topFieldsRow.spacing = 15
        topFieldsRow.distribution = .fill
        
        nameField = createEditField(title: L10n.isFrench ? "Nom" : "Name", value: skill.name)
        triggerField = createEditField(title: L10n.isFrench ? "Commande" : "Trigger", value: skill.trigger)
        
        colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (name, _) in colors {
            colorPopup.addItem(withTitle: name.capitalized)
            colorPopup.lastItem?.representedObject = name
        }
        colorPopup.selectItem(withTitle: skill.color.capitalized)
        colorPopup.target = self
        colorPopup.action = #selector(colorChanged(_:))
        
        topFieldsRow.addArrangedSubview(nameField)
        topFieldsRow.addArrangedSubview(triggerField)
        topFieldsRow.addArrangedSubview(colorPopup)
        
        detailStack.addArrangedSubview(topFieldsRow)
        
        // Prompt
        let promptLabel = NSTextField(labelWithString: L10n.isFrench ? "Instructions (Pre-prompt):" : "Instructions (Pre-prompt):")
        promptLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        promptLabel.textColor = .secondaryLabelColor
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        
        let contentSize = scrollView.contentSize
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        
        promptTextView = NSTextView(frame: .zero, textContainer: textContainer)
        promptTextView.string = skill.prompt
        promptTextView.drawsBackground = true
        promptTextView.delegate = self
        promptTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        promptTextView.textContainerInset = NSSize(width: 10, height: 10)
        
        scrollView.documentView = promptTextView
        
        detailStack.addArrangedSubview(promptLabel)
        detailStack.addArrangedSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 100),
            nameField.widthAnchor.constraint(equalToConstant: 150),
            triggerField.widthAnchor.constraint(equalToConstant: 150),
            colorPopup.widthAnchor.constraint(equalToConstant: 90)
        ])
        
        promptContainer.addSubview(detailStack)
        NSLayoutConstraint.activate([
            detailStack.topAnchor.constraint(equalTo: promptContainer.topAnchor),
            detailStack.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor),
            detailStack.bottomAnchor.constraint(equalTo: promptContainer.bottomAnchor)
        ])
        
        mainStack.addArrangedSubview(promptContainer)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    @objc private func toggleExpand() {
        isExpanded.toggle()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            promptContainer.isHidden = !isExpanded
            chevronBtn.image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
            
            layer?.backgroundColor = isExpanded ? 
                NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor : 
                NSColor.controlBackgroundColor.withAlphaComponent(0.2).cgColor
        }
    }
    
    @objc private func deleteSelf() {
        onDelete?(index)
    }
    
    @objc private func colorChanged(_ sender: NSPopUpButton) {
        if let colorName = sender.selectedItem?.representedObject as? String {
            skill.color = colorName
            colorIndicator.layer?.backgroundColor = colors[colorName]?.cgColor
            onUpdate?(index, skill)
        }
    }
    
    private func createEditField(title: String, value: String) -> NSTextField {
        let field = NSTextField()
        field.stringValue = value
        field.placeholderString = title
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.font = NSFont.systemFont(ofSize: 13)
        return field
    }
    
    // MARK: - Interaction
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedView = hitTest(point)
        if let view = clickedView, view.isDescendant(of: promptContainer) {
            return
        }
        if clickedView is NSButton || clickedView is NSTextField || clickedView is NSPopUpButton {
            return
        }
        toggleExpand()
    }
    
    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        if !isExpanded {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if !isExpanded {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.2).cgColor
        }
    }
    
    // MARK: - Delegates
    func controlTextDidChange(_ obj: Notification) {
        skill.name = nameField.stringValue
        skill.trigger = triggerField.stringValue
        nameLabel.stringValue = skill.name
        triggerLabel.stringValue = skill.trigger
        onUpdate?(index, skill)
    }
    
    func textDidChange(_ notification: Notification) {
        skill.prompt = promptTextView.string
        onUpdate?(index, skill)
    }
}
