import Cocoa
import Carbon.HIToolbox
import AVFoundation
import Combine

class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    private var sidebarView: SidebarView!
    private var contentContainer: NSView!
    private var sidebarEffectView: NSVisualEffectView!
    private var currentSectionView: NSView?
    
    // Cached views for sections
    private var generalView: NSView!
    private var historyView: NSView!
    private var aiView: NSView!
    private var vocabularyView: NSView!
    private var meetingsView: NSView!
    
    // Configuration controls
    private var historyToggle: NSSwitch!
    private var launchOnLoginToggle: NSSwitch!
    private var muteToggle: NSSwitch!
    private var showInDockToggle: NSSwitch!
    private var microphonePopup: NSPopUpButton!
    private var pttCard: ModeCardView!
    private var toggleCard: ModeCardView!
    private var hotkeyButton: HotkeyButton!
    private var aiModesStack: NSStackView!
    private var llmProviderPopup: NSPopUpButton!
    private var geminiModelPopup: NSPopUpButton!
    private var geminiModelBox: NSView!
    private var openaiModelPopup: NSPopUpButton!
    private var openaiModelBox: NSView!
    private var anthropicModelPopup: NSPopUpButton!
    private var anthropicModelBox: NSView!
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
    
    // Meetings controls
    private var meetingsTableView: NSTableView!
    private var meetingsData: [Meeting] = []
    private var meetingsEmptyStateView: NSView?
    private var meetingStartButton: NSButton!
    private var speakerDirectoryStack: NSStackView!
    private var enrollmentAudioBuffer: [Float] = []
    private var enrollmentTimer: Timer?
    
    // Local AI Controls
    private var localAIToggle: NSSwitch!
    private var downloadProgressBar: NSProgressIndicator!
    private var downloadProgressLabel: NSTextField!
    private var downloadButton: NSButton!
    private var cancellables = Set<AnyCancellable>()
    private var activeReportWindow: MeetingDetailWindow?
    private var validationWorkItem: DispatchWorkItem?

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
        meetingsView = createMeetingsView()
        
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
        case config, meetings, ai, vocabulary, history
        
        var title: String {
            let l = L10n.current
            switch self {
            case .config: return l.generalTab
            case .history: return l.historyTab
            case .meetings: return L10n.isFrench ? "Réunions" : "Meetings"
            case .ai: return l.aiAssistantTab
            case .vocabulary: return l.vocabularyTab
            }
        }
        
        var iconName: String {
            switch self {
            case .config: return "gearshape.fill"
            case .history: return "clock.arrow.circlepath"
            case .meetings: return "person.3.fill"
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
        case .meetings: targetView = meetingsView
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
        
        let cardsRow = NSStackView(views: [cardsStack])
        cardsRow.translatesAutoresizingMaskIntoConstraints = false
        cardsRow.alignment = .leading
        cardsRow.edgeInsets = NSEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        
        NSLayoutConstraint.activate([
            cardsStack.heightAnchor.constraint(equalToConstant: 140),
            cardsStack.leadingAnchor.constraint(equalTo: cardsRow.leadingAnchor),
            cardsStack.trailingAnchor.constraint(equalTo: cardsRow.trailingAnchor, constant: -16),
        ])
        
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
                title: L10n.isFrench ? "Afficher dans le Dock" : "Show in Dock",
                description: L10n.isFrench ? "Afficher l'icône de l'application dans le Dock (nécessite un redémarrage)." : "Show application icon in the Dock (requires restart).",
                control: {
                    let toggle = NSSwitch()
                    toggle.translatesAutoresizingMaskIntoConstraints = false
                    toggle.target = self
                    toggle.action = #selector(self.showInDockChanged)
                    self.showInDockToggle = toggle
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
        init(customView: NSView) {
            super.init(frame: .zero)
            setupStyle()
            
            customView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(customView)
            NSLayoutConstraint.activate([
                customView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
                customView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                customView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                customView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
            ])
        }

        init(rows: [NSView]) {
            super.init(frame: .zero)
            setupStyle()
            
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

        private func setupStyle() {
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
    
    class MeetingRowView: NSTableCellView {
        private let titleLabel = NSTextField()
        private let dateLabel = NSTextField()
        private let infoLabel = NSTextField()
        private let avatarsStack = NSStackView()
        private let cardView = NSView()
        
        override init(frame: NSRect) {
            super.init(frame: frame)
            setupUI()
        }
        
        required init?(coder: NSCoder) { fatalError() }
        
        private func setupUI() {
            cardView.translatesAutoresizingMaskIntoConstraints = false
            cardView.wantsLayer = true
            cardView.layer?.cornerRadius = 10
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                cardView.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
            } else {
                cardView.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.5).cgColor
            }
            addSubview(cardView)
            
            titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
            titleLabel.textColor = .labelColor
            titleLabel.isEditable = false
            titleLabel.isSelectable = false
            titleLabel.drawsBackground = false
            titleLabel.isBordered = false
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            
            dateLabel.font = NSFont.systemFont(ofSize: 11)
            dateLabel.textColor = .secondaryLabelColor
            dateLabel.isEditable = false
            dateLabel.isSelectable = false
            dateLabel.drawsBackground = false
            dateLabel.isBordered = false
            dateLabel.translatesAutoresizingMaskIntoConstraints = false
            
            infoLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            infoLabel.textColor = .controlAccentColor
            infoLabel.isEditable = false
            infoLabel.isSelectable = false
            infoLabel.drawsBackground = false
            infoLabel.isBordered = false
            infoLabel.translatesAutoresizingMaskIntoConstraints = false
            
            avatarsStack.orientation = .horizontal
            avatarsStack.spacing = -8 // Overlapping avatars
            avatarsStack.translatesAutoresizingMaskIntoConstraints = false
            
            cardView.addSubview(titleLabel)
            cardView.addSubview(dateLabel)
            cardView.addSubview(avatarsStack)
            
            NSLayoutConstraint.activate([
                cardView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
                
                titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
                titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -16),
                
                dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
                dateLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
                dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: avatarsStack.leadingAnchor, constant: -8),
                
                avatarsStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
                avatarsStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
            ])
        }
        
        func configure(meeting: Meeting) {
            titleLabel.stringValue = meeting.title
            dateLabel.stringValue = meeting.date.formatted(date: .long, time: .shortened)
            
            refreshAvatars(for: meeting)
        }
        
        private func refreshAvatars(for meeting: Meeting) {
            avatarsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            let resolvedProfiles = meeting.participantIds.prefix(4).compactMap { id in
                SpeakerEnrollmentManager.shared.profiles.first { $0.id == id }
            }
            for profile in resolvedProfiles {
                let avatar = createAvatar(for: profile)
                avatarsStack.addArrangedSubview(avatar)
            }
            
            if meeting.participantIds.count > 4 {
                let more = NSTextField(labelWithString: "+\(meeting.participantIds.count - 4)")
                more.font = NSFont.systemFont(ofSize: 10, weight: .bold)
                more.textColor = .secondaryLabelColor
                avatarsStack.addArrangedSubview(more)
            }
        }
        
        private func createAvatar(for profile: SpeakerProfile) -> NSView {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.widthAnchor.constraint(equalToConstant: 24).isActive = true
            container.heightAnchor.constraint(equalToConstant: 24).isActive = true
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(hex: profile.colorHex)?.cgColor ?? NSColor.systemBlue.cgColor
            container.layer?.cornerRadius = 12
            container.layer?.borderWidth = 1.5
            container.layer?.borderColor = NSColor.windowBackgroundColor.cgColor
            
            let label = NSTextField(labelWithString: profile.initials)
            label.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            
            return container
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
        
        // 1. Header
        let title = createMainTitle(l.aiAssistantTab)
        mainStack.addArrangedSubview(title)
        
        // 2. Provider Selection
        mainStack.addArrangedSubview(createSectionHeader(l.llmProviderLabel))
        
        let providerBox = SettingsGroupBox(rows: [
            createSettingRow(
                title: l.aiAssistantModel,
                description: L10n.isFrench ? "Choisissez le modèle d'IA" : "Choose the AI model",
                control: {
                    let popup = NSPopUpButton()
                    popup.translatesAutoresizingMaskIntoConstraints = false
                    popup.target = self
                    popup.action = #selector(llmProviderChanged(_:))
                    self.llmProviderPopup = popup
                    
                    // Populate
                    for provider in SettingsManager.LLMProvider.allCases {
                        popup.addItem(withTitle: provider.displayName)
                        popup.lastItem?.representedObject = provider
                    }
                    
                    // Select current
                    let current = SettingsManager.shared.llmProvider
                    if let idx = SettingsManager.LLMProvider.allCases.firstIndex(of: current) {
                        popup.selectItem(at: idx)
                    }
                    
                    return popup
                }()
            )
        ])
        mainStack.addArrangedSubview(providerBox)
        providerBox.widthAnchor.constraint(equalToConstant: 580).isActive = true
        
        // 2b. Gemini Model Selection (only visible when Google is selected)
        let geminiModelSettingBox = SettingsGroupBox(rows: [
            createSettingRow(
                title: L10n.isFrench ? "Modèle Gemini" : "Gemini Model",
                description: L10n.isFrench ? "Choisissez le modèle Gemini à utiliser" : "Choose which Gemini model to use",
                control: {
                    let popup = NSPopUpButton()
                    popup.translatesAutoresizingMaskIntoConstraints = false
                    popup.target = self
                    popup.action = #selector(geminiModelChanged(_:))
                    self.geminiModelPopup = popup
                    
                    let currentModelId = SettingsManager.shared.geminiModelId
                    for model in Constants.GeminiModel.allModels {
                        popup.addItem(withTitle: model.displayName)
                        popup.lastItem?.representedObject = model.id
                        if model.id == currentModelId {
                            popup.select(popup.lastItem)
                        }
                    }
                    
                    return popup
                }()
            )
        ])
        self.geminiModelBox = geminiModelSettingBox
        geminiModelSettingBox.widthAnchor.constraint(equalToConstant: 580).isActive = true
        geminiModelSettingBox.isHidden = (SettingsManager.shared.llmProvider != .google)
        mainStack.addArrangedSubview(geminiModelSettingBox)
        
        // 2c. OpenAI Model Selection (only visible when OpenAI is selected)
        let openaiModelSettingBox = SettingsGroupBox(rows: [
            createSettingRow(
                title: L10n.isFrench ? "Modèle OpenAI" : "OpenAI Model",
                description: L10n.isFrench ? "Choisissez le modèle OpenAI à utiliser" : "Choose which OpenAI model to use",
                control: {
                    let popup = NSPopUpButton()
                    popup.translatesAutoresizingMaskIntoConstraints = false
                    popup.target = self
                    popup.action = #selector(openaiModelChanged(_:))
                    self.openaiModelPopup = popup
                    
                    let currentModelId = SettingsManager.shared.openaiModelId
                    for model in Constants.OpenAIModel.allModels {
                        popup.addItem(withTitle: model.displayName)
                        popup.lastItem?.representedObject = model.id
                        if model.id == currentModelId {
                            popup.select(popup.lastItem)
                        }
                    }
                    
                    return popup
                }()
            )
        ])
        self.openaiModelBox = openaiModelSettingBox
        openaiModelSettingBox.widthAnchor.constraint(equalToConstant: 580).isActive = true
        openaiModelSettingBox.isHidden = (SettingsManager.shared.llmProvider != .openai)
        mainStack.addArrangedSubview(openaiModelSettingBox)
        
        // 2d. Anthropic Model Selection (only visible when Anthropic is selected)
        let anthropicModelSettingBox = SettingsGroupBox(rows: [
            createSettingRow(
                title: L10n.isFrench ? "Modèle Anthropic" : "Anthropic Model",
                description: L10n.isFrench ? "Choisissez le modèle Anthropic à utiliser" : "Choose which Anthropic model to use",
                control: {
                    let popup = NSPopUpButton()
                    popup.translatesAutoresizingMaskIntoConstraints = false
                    popup.target = self
                    popup.action = #selector(anthropicModelChanged(_:))
                    self.anthropicModelPopup = popup
                    
                    let currentModelId = SettingsManager.shared.anthropicModelId
                    for model in Constants.AnthropicModel.allModels {
                        popup.addItem(withTitle: model.displayName)
                        popup.lastItem?.representedObject = model.id
                        if model.id == currentModelId {
                            popup.select(popup.lastItem)
                        }
                    }
                    
                    return popup
                }()
            )
        ])
        self.anthropicModelBox = anthropicModelSettingBox
        anthropicModelSettingBox.widthAnchor.constraint(equalToConstant: 580).isActive = true
        anthropicModelSettingBox.isHidden = (SettingsManager.shared.llmProvider != .anthropic)
        mainStack.addArrangedSubview(anthropicModelSettingBox)
        
        // 3. API Key Section
        self.apiKeyStack = NSStackView()
        apiKeyStack.translatesAutoresizingMaskIntoConstraints = false
        apiKeyStack.orientation = .vertical
        apiKeyStack.alignment = .leading
        apiKeyStack.spacing = 24
        
        let apiKeyContent = NSStackView()
        apiKeyContent.orientation = .vertical
        apiKeyContent.alignment = .leading
        apiKeyContent.spacing = 10
        apiKeyContent.translatesAutoresizingMaskIntoConstraints = false
        
        let apiLabelStack = NSStackView()
        apiLabelStack.orientation = .vertical
        apiLabelStack.alignment = .leading
        apiLabelStack.spacing = 2
        
        let apiTitle = NSTextField(labelWithString: l.apiKeyLabel)
        apiTitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        
        let apiDesc = NSTextField(labelWithString: L10n.isFrench ? "Votre clé API privée (stockée localement)" : "Your private API Key (stored locally)")
        apiDesc.font = NSFont.systemFont(ofSize: 11)
        apiDesc.textColor = .secondaryLabelColor
        
        apiLabelStack.addArrangedSubview(apiTitle)
        apiLabelStack.addArrangedSubview(apiDesc)
        
        let fieldRow = NSStackView()
        fieldRow.orientation = .horizontal
        fieldRow.alignment = .centerY
        fieldRow.spacing = 12
        fieldRow.translatesAutoresizingMaskIntoConstraints = false
        
        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .exterior
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.target = self
        field.action = #selector(apiKeyChanged(_:))
        field.delegate = self
        field.placeholderString = "sk-..."
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) 
        self.apiKeyField = field
        
        fieldRow.addArrangedSubview(field)
        
        apiKeyContent.addArrangedSubview(apiLabelStack)
        apiKeyContent.addArrangedSubview(fieldRow)
        
        let apiKeyBox = SettingsGroupBox(customView: apiKeyContent)
        
        NSLayoutConstraint.activate([
            field.heightAnchor.constraint(equalToConstant: 28),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
            fieldRow.widthAnchor.constraint(equalTo: apiKeyContent.widthAnchor)
        ])
        apiKeyBox.widthAnchor.constraint(equalToConstant: 580).isActive = true
        
        let validationStack = NSStackView()
        validationStack.orientation = .horizontal
        validationStack.spacing = 12
        
        let validateBtn = NSButton(title: "Test Connection", target: self, action: #selector(testAPIConnection))
        validateBtn.bezelStyle = .rounded
        
        self.statusIndicator = NSImageView()
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        statusIndicator.widthAnchor.constraint(equalToConstant: 16).isActive = true
        statusIndicator.heightAnchor.constraint(equalToConstant: 16).isActive = true
        statusIndicator.isHidden = true
        
        self.cloudModelLabel = NSTextField(labelWithString: "")
        cloudModelLabel.font = NSFont.systemFont(ofSize: 11)
        cloudModelLabel.textColor = .secondaryLabelColor
        
        self.localModelLabel = NSTextField(labelWithString: "")
        localModelLabel.isHidden = true

        validationStack.addArrangedSubview(validateBtn)
        validationStack.addArrangedSubview(statusIndicator)
        validationStack.addArrangedSubview(cloudModelLabel)
        
        apiKeyStack.addArrangedSubview(createSectionHeader("Configuration API"))
        apiKeyStack.addArrangedSubview(apiKeyBox)
        apiKeyStack.addArrangedSubview(validationStack)
        
        mainStack.addArrangedSubview(apiKeyStack)
        
        // 4. Custom Skills Section
        mainStack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "Compétences Personnalisées" : "Custom AI Skills"))
        
        self.aiModesStack = NSStackView()
        aiModesStack.translatesAutoresizingMaskIntoConstraints = false
        aiModesStack.orientation = .vertical
        aiModesStack.alignment = .centerX
        aiModesStack.spacing = 8
        mainStack.addArrangedSubview(aiModesStack)
        
        // Add Button
        let addBtn = NSButton(title: L10n.isFrench ? "Ajouter une compétence" : "Add AI Skill", target: self, action: #selector(addAISkill))
        addBtn.bezelStyle = .rounded
        mainStack.addArrangedSubview(addBtn)
        
        // Update visibility based on initial state
        updateAIViewVisibility()
        
        return container
    }
    

    
    @objc private func testAPIConnection() {
        let provider = SettingsManager.shared.llmProvider
        let key = self.apiKeyField.stringValue
        
        statusIndicator.isHidden = false
        statusIndicator.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Checking")
        statusIndicator.contentTintColor = .secondaryLabelColor
        
        Task {
            do {
                let (isValid, modelName) = try await LLMManager.shared.validateApiKey(provider: provider, apiKey: key)
                DispatchQueue.main.async {
                    if isValid {
                        self.statusIndicator.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Valid")
                        self.statusIndicator.contentTintColor = .systemGreen
                        
                        if let modelName = modelName {
                             self.cloudModelLabel.stringValue = "Model: \(modelName)"
                        }
                    } else {
                        self.statusIndicator.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Invalid")
                        self.statusIndicator.contentTintColor = .systemRed
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusIndicator.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
                    self.statusIndicator.contentTintColor = .systemOrange
                }
            }
        }
    }

    @objc private func apiKeyChanged(_ sender: NSTextField) {
        let provider = SettingsManager.shared.llmProvider
        let key = sender.stringValue
        
        switch provider {
        case .openai: SettingsManager.shared.openaiApiKey = key
        case .google: SettingsManager.shared.geminiApiKey = key
        case .anthropic: SettingsManager.shared.anthropicApiKey = key
        default: break
        }
        
        // Clear indicator on change
        statusIndicator.isHidden = true
    }
    
    private func updateAIViewVisibility() {
        let provider = SettingsManager.shared.llmProvider
        
        if provider == .none {
            apiKeyStack.isHidden = true
        } else {
            apiKeyStack.isHidden = false
            
            // Populate field
            switch provider {
            case .openai: apiKeyField.stringValue = SettingsManager.shared.openaiApiKey
            case .google: apiKeyField.stringValue = SettingsManager.shared.geminiApiKey
            case .anthropic: apiKeyField.stringValue = SettingsManager.shared.anthropicApiKey
            default: apiKeyField.stringValue = ""
            }
        }
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
    
    private func createMeetingsView() -> NSView {
        let container = NSView()
        
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = documentView
        container.addSubview(scroll)
        
        let mainStack = NSStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 32
        mainStack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        documentView.addSubview(mainStack)
        
        // ═══════════════════════════════════════
        // SECTION A — Big Start/Stop Button
        // ═══════════════════════════════════════
        let buttonSection = NSView()
        buttonSection.translatesAutoresizingMaskIntoConstraints = false
        buttonSection.wantsLayer = true
        buttonSection.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        buttonSection.layer?.cornerRadius = 16
        
        meetingStartButton = NSButton()
        meetingStartButton.translatesAutoresizingMaskIntoConstraints = false
        meetingStartButton.bezelStyle = .rounded
        meetingStartButton.isBordered = false
        meetingStartButton.wantsLayer = true
        meetingStartButton.layer?.cornerRadius = 28
        meetingStartButton.target = self
        meetingStartButton.action = #selector(toggleMeetingAction)
        
        updateMeetingButtonState()
        
        buttonSection.addSubview(meetingStartButton)
        
        NSLayoutConstraint.activate([
            buttonSection.heightAnchor.constraint(equalToConstant: 120),
            meetingStartButton.centerXAnchor.constraint(equalTo: buttonSection.centerXAnchor),
            meetingStartButton.centerYAnchor.constraint(equalTo: buttonSection.centerYAnchor),
            meetingStartButton.widthAnchor.constraint(equalToConstant: 320),
            meetingStartButton.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        mainStack.addArrangedSubview(buttonSection)
        buttonSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -80).isActive = true
        
        // ═══════════════════════════════════════
        // SECTION B — Speaker Directory
        // ═══════════════════════════════════════
        let dirSection = NSView()
        dirSection.translatesAutoresizingMaskIntoConstraints = false
        dirSection.wantsLayer = true
        dirSection.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3).cgColor
        dirSection.layer?.cornerRadius = 12
        
        let dirHeader = NSStackView()
        dirHeader.translatesAutoresizingMaskIntoConstraints = false
        dirHeader.orientation = .horizontal
        dirHeader.alignment = .centerY
        dirHeader.spacing = 8
        
        let dirTitle = NSTextField(labelWithString: L10n.isFrench ? "Participants Enregistrés" : "Enrolled Speakers")
        dirTitle.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        dirTitle.textColor = .labelColor
        dirHeader.addArrangedSubview(dirTitle)
        
        let dirSpacer = NSView()
        dirSpacer.translatesAutoresizingMaskIntoConstraints = false
        dirHeader.addArrangedSubview(dirSpacer)
        
        let addSpeakerBtn = NSButton(title: L10n.isFrench ? "＋ Ajouter" : "＋ Add", target: self, action: #selector(showEnrollmentModal))
        addSpeakerBtn.bezelStyle = .rounded
        addSpeakerBtn.controlSize = .regular
        addSpeakerBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        dirHeader.addArrangedSubview(addSpeakerBtn)
        
        speakerDirectoryStack = NSStackView()
        speakerDirectoryStack.translatesAutoresizingMaskIntoConstraints = false
        speakerDirectoryStack.orientation = .vertical
        speakerDirectoryStack.alignment = .leading
        speakerDirectoryStack.spacing = 8
        
        dirSection.addSubview(dirHeader)
        dirSection.addSubview(speakerDirectoryStack)
        
        NSLayoutConstraint.activate([
            dirHeader.topAnchor.constraint(equalTo: dirSection.topAnchor, constant: 16),
            dirHeader.leadingAnchor.constraint(equalTo: dirSection.leadingAnchor, constant: 16),
            dirHeader.trailingAnchor.constraint(equalTo: dirSection.trailingAnchor, constant: -16),
            
            speakerDirectoryStack.topAnchor.constraint(equalTo: dirHeader.bottomAnchor, constant: 16),
            speakerDirectoryStack.leadingAnchor.constraint(equalTo: dirSection.leadingAnchor, constant: 16),
            speakerDirectoryStack.trailingAnchor.constraint(equalTo: dirSection.trailingAnchor, constant: -16),
            speakerDirectoryStack.bottomAnchor.constraint(equalTo: dirSection.bottomAnchor, constant: -16)
        ])
        
        mainStack.addArrangedSubview(dirSection)
        dirSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -80).isActive = true
        
        // ═══════════════════════════════════════
        // SECTION C — Meeting History
        // ═══════════════════════════════════════
        let histSection = NSView()
        histSection.translatesAutoresizingMaskIntoConstraints = false
        
        let histTitle = NSTextField(labelWithString: L10n.isFrench ? "Historique des Réunions" : "Meeting History")
        histTitle.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        histTitle.textColor = .labelColor
        histTitle.translatesAutoresizingMaskIntoConstraints = false
        histSection.addSubview(histTitle)
        
        meetingsTableView = NSTableView()
        meetingsTableView.delegate = self
        meetingsTableView.dataSource = self
        meetingsTableView.backgroundColor = .clear
        meetingsTableView.usesAlternatingRowBackgroundColors = false
        meetingsTableView.rowHeight = 70
        meetingsTableView.intercellSpacing = NSSize(width: 0, height: 10)
        meetingsTableView.headerView = nil
        meetingsTableView.selectionHighlightStyle = .regular
        meetingsTableView.target = self
        meetingsTableView.doubleAction = #selector(viewSelectedMeetingReport)
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("meeting"))
        col.resizingMask = .autoresizingMask
        meetingsTableView.addTableColumn(col)
        
        let meetingScroll = NSScrollView()
        meetingScroll.translatesAutoresizingMaskIntoConstraints = false
        meetingScroll.hasVerticalScroller = true
        meetingScroll.autohidesScrollers = true
        meetingScroll.borderType = .noBorder
        meetingScroll.drawsBackground = false
        meetingScroll.documentView = meetingsTableView
        histSection.addSubview(meetingScroll)
        
        // Empty State
        let emptyState = NSStackView()
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 12
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        
        let emptyIcon = NSImageView(image: NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: nil)!)
        emptyIcon.contentTintColor = .tertiaryLabelColor
        emptyIcon.symbolConfiguration = .init(pointSize: 36, weight: .regular)
        
        let emptyTitle = NSTextField(labelWithString: L10n.isFrench ? "Aucune réunion" : "No Meetings Yet")
        emptyTitle.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        emptyTitle.textColor = .secondaryLabelColor
        
        let emptySub = NSTextField(labelWithString: L10n.isFrench ? "Cliquez sur le bouton ci-dessus pour commencer." : "Click the button above to start a meeting.")
        emptySub.font = NSFont.systemFont(ofSize: 12)
        emptySub.textColor = .tertiaryLabelColor
        
        emptyState.addArrangedSubview(emptyIcon)
        emptyState.addArrangedSubview(emptyTitle)
        emptyState.addArrangedSubview(emptySub)
        histSection.addSubview(emptyState)
        self.meetingsEmptyStateView = emptyState
        
        NSLayoutConstraint.activate([
            histTitle.topAnchor.constraint(equalTo: histSection.topAnchor),
            histTitle.leadingAnchor.constraint(equalTo: histSection.leadingAnchor),
            
            meetingScroll.topAnchor.constraint(equalTo: histTitle.bottomAnchor, constant: 12),
            meetingScroll.leadingAnchor.constraint(equalTo: histSection.leadingAnchor),
            meetingScroll.trailingAnchor.constraint(equalTo: histSection.trailingAnchor),
            meetingScroll.bottomAnchor.constraint(equalTo: histSection.bottomAnchor),
            meetingScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            
            emptyState.centerXAnchor.constraint(equalTo: meetingScroll.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: meetingScroll.centerYAnchor)
        ])
        
        mainStack.addArrangedSubview(histSection)
        histSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -80).isActive = true
        
        // ═══════════════════════════════════════
        // Layout
        // ═══════════════════════════════════════
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            documentView.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            
            mainStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            mainStack.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])
        
        // Load data
        refreshSpeakerDirectory()
        loadMeetings()
        
        return container
    }
    
    // MARK: - Meeting Button State
    
    private func updateMeetingButtonState() {
        let isActive = MeetingManager.shared.isMeetingActive
        
        if isActive {
            meetingStartButton.title = L10n.isFrench ? "⏹  Terminer la Réunion" : "⏹  End Meeting"
            meetingStartButton.contentTintColor = .white
            meetingStartButton.layer?.backgroundColor = NSColor.systemRed.cgColor
            
            // Pulse animation
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.85
            pulse.duration = 1.0
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            meetingStartButton.layer?.add(pulse, forKey: "recordPulse")
        } else {
            meetingStartButton.title = L10n.isFrench ? "🎙️  Démarrer une Réunion" : "🎙️  Start Meeting"
            meetingStartButton.contentTintColor = .white
            meetingStartButton.layer?.backgroundColor = Constants.brandBlue.cgColor
            meetingStartButton.layer?.removeAnimation(forKey: "recordPulse")
        }
        
        meetingStartButton.font = NSFont.systemFont(ofSize: 17, weight: .bold)
    }
    
    @objc private func toggleMeetingAction() {
        if MeetingManager.shared.isMeetingActive {
            // Stop meeting
            MeetingManager.shared.stopMeeting()
            updateMeetingButtonState()
            
            // Refresh history after processing
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.loadMeetings()
            }
        } else {
            // Show modal to start meeting
            showStartMeetingModal()
        }
    }
    
    private func showStartMeetingModal() {
        let alert = NSAlert()
        alert.messageText = L10n.isFrench ? "Nouvelle Réunion" : "New Meeting"
        alert.informativeText = L10n.isFrench ? "Entrez un nom pour cette réunion" : "Enter a name for this meeting"
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        inputField.placeholderString = formatter.string(from: Date())
        inputField.font = NSFont.systemFont(ofSize: 14)
        alert.accessoryView = inputField
        
        alert.addButton(withTitle: L10n.isFrench ? "Démarrer" : "Start")
        alert.addButton(withTitle: L10n.isFrench ? "Annuler" : "Cancel")
        
        alert.window.initialFirstResponder = inputField
        
        if alert.runModal() == .alertFirstButtonReturn {
            var title = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                title = formatter.string(from: Date())
            }
            
            MeetingManager.shared.startMeeting(title: title)
            updateMeetingButtonState()
        }
    }
    
    // MARK: - Speaker Directory
    
    private func refreshSpeakerDirectory() {
        speakerDirectoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let profiles = SpeakerEnrollmentManager.shared.profiles
        
        if profiles.isEmpty {
            let empty = NSTextField(labelWithString: L10n.isFrench ? "Aucun participant enregistré. Ajoutez des participants pour les identifier automatiquement." : "No enrolled speakers. Add participants to automatically identify them.")
            empty.font = NSFont.systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            empty.preferredMaxLayoutWidth = 400
            speakerDirectoryStack.addArrangedSubview(empty)
            return
        }
        
        // Group speakers
        let groups = SpeakerEnrollmentManager.shared.groupedProfiles
        
        for group in groups {
            // Group header
            let groupHeader = NSTextField(labelWithString: group.name.uppercased())
            groupHeader.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            groupHeader.textColor = .tertiaryLabelColor
            speakerDirectoryStack.addArrangedSubview(groupHeader)
            
            for profile in group.members {
                let row = createSpeakerDirectoryRow(profile: profile)
                speakerDirectoryStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: speakerDirectoryStack.widthAnchor).isActive = true
            }
            
            // Separator
            let sep = NSView()
            sep.translatesAutoresizingMaskIntoConstraints = false
            sep.wantsLayer = true
            sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
            sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            speakerDirectoryStack.addArrangedSubview(sep)
            sep.widthAnchor.constraint(equalTo: speakerDirectoryStack.widthAnchor).isActive = true
        }
    }
    
    private func createSpeakerDirectoryRow(profile: SpeakerProfile) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        
        // Avatar
        let avatar = NSView()
        avatar.wantsLayer = true
        avatar.layer?.backgroundColor = NSColor(hex: profile.colorHex)?.cgColor ?? NSColor.systemBlue.cgColor
        avatar.layer?.cornerRadius = 16
        avatar.translatesAutoresizingMaskIntoConstraints = false
        
        let initials = NSTextField(labelWithString: profile.initials)
        initials.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        initials.textColor = .white
        initials.alignment = .center
        initials.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(initials)
        
        // Name + Role
        let hasSubtitle = !profile.role.isEmpty || !profile.groupName.isEmpty
        
        let nameLabel = NSTextField(labelWithString: profile.name)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let roleLabel = NSTextField(labelWithString: profile.role.isEmpty ? profile.groupName : profile.role)
        roleLabel.font = NSFont.systemFont(ofSize: 11)
        roleLabel.textColor = .secondaryLabelColor
        roleLabel.translatesAutoresizingMaskIntoConstraints = false
        roleLabel.isHidden = !hasSubtitle
        
        // Edit button
        let editBtn = NSButton()
        editBtn.translatesAutoresizingMaskIntoConstraints = false
        editBtn.bezelStyle = .circular
        editBtn.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit")
        editBtn.isBordered = false
        editBtn.contentTintColor = .secondaryLabelColor
        editBtn.target = self
        editBtn.action = #selector(editSpeakerAction(_:))
        editBtn.identifier = NSUserInterfaceItemIdentifier(profile.id)
        
        // Delete button
        let deleteBtn = NSButton()
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.bezelStyle = .circular
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteBtn.isBordered = false
        deleteBtn.contentTintColor = .systemRed
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteSpeakerAction(_:))
        deleteBtn.tag = profile.id.hashValue
        deleteBtn.identifier = NSUserInterfaceItemIdentifier(profile.id)
        
        row.addSubview(avatar)
        row.addSubview(nameLabel)
        row.addSubview(roleLabel)
        row.addSubview(editBtn)
        row.addSubview(deleteBtn)
        
        var constraints = [
            row.heightAnchor.constraint(equalToConstant: 44),
            
            avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            avatar.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32),
            
            initials.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            initials.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            
            nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            
            editBtn.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -4),
            editBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            editBtn.widthAnchor.constraint(equalToConstant: 24),
            editBtn.heightAnchor.constraint(equalToConstant: 24),
            
            deleteBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
            deleteBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            deleteBtn.widthAnchor.constraint(equalToConstant: 24),
            deleteBtn.heightAnchor.constraint(equalToConstant: 24)
        ]
        
        if hasSubtitle {
            constraints.append(nameLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 6))
            constraints.append(roleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor))
            constraints.append(roleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1))
        } else {
            // Center name vertically when no role/group
            constraints.append(nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor))
        }
        
        NSLayoutConstraint.activate(constraints)
        
        return row
    }
    
    @objc private func editSpeakerAction(_ sender: NSButton) {
        guard let profileId = sender.identifier?.rawValue else { return }
        guard let profile = SpeakerEnrollmentManager.shared.profiles.first(where: { $0.id == profileId }) else { return }
        
        let alert = NSAlert()
        alert.messageText = L10n.isFrench ? "Modifier le participant" : "Edit Speaker"
        alert.informativeText = L10n.isFrench ? "Modifiez les informations du participant." : "Update the speaker's information."
        
        let formView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 110))
        
        let nameLabel = NSTextField(labelWithString: L10n.isFrench ? "Nom:" : "Name:")
        nameLabel.frame = NSRect(x: 0, y: 82, width: 60, height: 20)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        let nameField = NSTextField(frame: NSRect(x: 65, y: 80, width: 270, height: 24))
        nameField.stringValue = profile.name
        nameField.font = NSFont.systemFont(ofSize: 13)
        
        let roleLabel = NSTextField(labelWithString: L10n.isFrench ? "Rôle:" : "Role:")
        roleLabel.frame = NSRect(x: 0, y: 52, width: 60, height: 20)
        roleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        let roleField = NSTextField(frame: NSRect(x: 65, y: 50, width: 270, height: 24))
        roleField.stringValue = profile.role
        roleField.placeholderString = L10n.isFrench ? "ex: Product Manager" : "e.g. Product Manager"
        roleField.font = NSFont.systemFont(ofSize: 13)
        
        let groupLabel = NSTextField(labelWithString: L10n.isFrench ? "Groupe:" : "Group:")
        groupLabel.frame = NSRect(x: 0, y: 22, width: 60, height: 20)
        groupLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        let groupField = NSTextField(frame: NSRect(x: 65, y: 20, width: 270, height: 24))
        groupField.stringValue = profile.groupName
        groupField.placeholderString = L10n.isFrench ? "ex: Marketing" : "e.g. Marketing"
        groupField.font = NSFont.systemFont(ofSize: 13)
        
        formView.addSubview(nameLabel)
        formView.addSubview(nameField)
        formView.addSubview(roleLabel)
        formView.addSubview(roleField)
        formView.addSubview(groupLabel)
        formView.addSubview(groupField)
        
        alert.accessoryView = formView
        alert.addButton(withTitle: L10n.isFrench ? "Enregistrer" : "Save")
        alert.addButton(withTitle: L10n.isFrench ? "Annuler" : "Cancel")
        alert.window.initialFirstResponder = nameField
        
        if alert.runModal() == .alertFirstButtonReturn {
            let newName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else { return }
            let newRole = roleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newGroup = groupField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            SpeakerEnrollmentManager.shared.updateProfile(id: profileId, name: newName, role: newRole, groupName: newGroup)
            refreshSpeakerDirectory()
        }
    }
    
    @objc private func deleteSpeakerAction(_ sender: NSButton) {
        guard let profileId = sender.identifier?.rawValue else { return }
        SpeakerEnrollmentManager.shared.deleteProfile(id: profileId)
        refreshSpeakerDirectory()
    }
    
    @objc private func showEnrollmentModal() {
        let alert = NSAlert()
        alert.messageText = L10n.isFrench ? "Enregistrer un Participant" : "Enroll a Speaker"
        alert.informativeText = L10n.isFrench ? "Remplissez les informations et l'utilisateur devra parler pendant 5 secondes." : "Fill in the details. The participant will need to speak for 5 seconds."
        
        // Create a form view
        let formView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 110))
        
        let nameLabel = NSTextField(labelWithString: L10n.isFrench ? "Nom:" : "Name:")
        nameLabel.frame = NSRect(x: 0, y: 82, width: 60, height: 20)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        let nameField = NSTextField(frame: NSRect(x: 65, y: 80, width: 270, height: 24))
        nameField.placeholderString = L10n.isFrench ? "Prénom Nom" : "First Last"
        nameField.font = NSFont.systemFont(ofSize: 13)
        
        let roleLabel = NSTextField(labelWithString: L10n.isFrench ? "Rôle:" : "Role:")
        roleLabel.frame = NSRect(x: 0, y: 52, width: 60, height: 20)
        roleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        let roleField = NSTextField(frame: NSRect(x: 65, y: 50, width: 270, height: 24))
        roleField.placeholderString = L10n.isFrench ? "ex: Product Manager" : "e.g. Product Manager"
        roleField.font = NSFont.systemFont(ofSize: 13)
        
        let groupLabel = NSTextField(labelWithString: L10n.isFrench ? "Groupe:" : "Group:")
        groupLabel.frame = NSRect(x: 0, y: 22, width: 60, height: 20)
        groupLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        let groupField = NSTextField(frame: NSRect(x: 65, y: 20, width: 270, height: 24))
        groupField.placeholderString = L10n.isFrench ? "ex: Marketing, Dev, Direction" : "e.g. Marketing, Engineering"
        groupField.font = NSFont.systemFont(ofSize: 13)
        
        formView.addSubview(nameLabel)
        formView.addSubview(nameField)
        formView.addSubview(roleLabel)
        formView.addSubview(roleField)
        formView.addSubview(groupLabel)
        formView.addSubview(groupField)
        
        alert.accessoryView = formView
        alert.addButton(withTitle: L10n.isFrench ? "Enregistrer la voix" : "Record Voice")
        alert.addButton(withTitle: L10n.isFrench ? "Annuler" : "Cancel")
        alert.window.initialFirstResponder = nameField
        
        if alert.runModal() == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let role = roleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = groupField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !name.isEmpty else { return }
            
            startVoiceEnrollment(name: name, role: role, group: group)
        }
    }
    
    private func startVoiceEnrollment(name: String, role: String, group: String) {
        // 1. Ensure models are loaded
        if TranscriptionManager.shared.diarizerModels == nil {
             // Show loading indicator overlay
             let loadingView = NSVisualEffectView()
             loadingView.material = .hudWindow
             loadingView.state = .active
             loadingView.wantsLayer = true
             loadingView.layer?.cornerRadius = 12
             loadingView.translatesAutoresizingMaskIntoConstraints = false
             
             let spinner = NSProgressIndicator()
             spinner.style = .spinning
             spinner.controlSize = .large
             spinner.translatesAutoresizingMaskIntoConstraints = false
             loadingView.addSubview(spinner)
             spinner.startAnimation(nil)
             
             let label = NSTextField(labelWithString: L10n.isFrench ? "Chargement des modèles..." : "Loading models...")
             label.translatesAutoresizingMaskIntoConstraints = false
             label.font = .systemFont(ofSize: 13, weight: .medium)
             label.textColor = .labelColor
             loadingView.addSubview(label)
             
             guard let contentView = self.contentView else { return }
             contentView.addSubview(loadingView)
             
             NSLayoutConstraint.activate([
                 loadingView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                 loadingView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                 loadingView.widthAnchor.constraint(equalToConstant: 220),
                 loadingView.heightAnchor.constraint(equalToConstant: 140),
                 
                 spinner.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
                 spinner.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor, constant: -15),
                 label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 15),
                 label.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor)
             ])
             
             Task {
                 do {
                     try await TranscriptionManager.shared.downloadDiarizerModels()
                     await MainActor.run {
                         loadingView.removeFromSuperview()
                         self.showEnrollmentRecorder(name: name, role: role, group: group)
                     }
                 } catch {
                     await MainActor.run {
                         loadingView.removeFromSuperview()
                         let alert = NSAlert()
                         alert.messageText = L10n.isFrench ? "Erreur" : "Error"
                         alert.informativeText = error.localizedDescription
                         alert.runModal()
                     }
                 }
             }
             return
        }
        
        showEnrollmentRecorder(name: name, role: role, group: group)
    }
    
    private func showEnrollmentRecorder(name: String, role: String, group: String) {
        guard let contentView = self.contentView else { return }
        
        let recorder = EnrollmentRecordingView()
        recorder.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(recorder)
        
        NSLayoutConstraint.activate([
            recorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            recorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            recorder.topAnchor.constraint(equalTo: contentView.topAnchor),
            recorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        recorder.onFinish = { [weak self, weak recorder] buffer in
            recorder?.removeFromSuperview()
            self?.finishEnrollment(buffer: buffer, name: name, role: role, group: group)
        }
        
        recorder.onCancel = { [weak recorder] in
            recorder?.removeFromSuperview()
        }
        
        recorder.startRecording()
    }
    
    private func finishEnrollment(buffer: [Float], name: String, role: String, group: String) {
        // Enforce minimum duration (e.g. 3 seconds ~ 48000 samples at 16kHz)
        let minSamples = 16000 * 3
        guard buffer.count >= minSamples else {
            let alert = NSAlert()
            alert.messageText = L10n.isFrench ? "Enregistrement trop court" : "Recording too short"
            alert.informativeText = L10n.isFrench ? "Veuillez parler pendant au moins 3 secondes." : "Please speak for at least 3 seconds."
            alert.runModal()
            
            // Retry? Or just close. Let's offer retry by re-showing recorder.
            self.showEnrollmentRecorder(name: name, role: role, group: group)
            return
        }
        
        // Check for silence
        let maxAmp = buffer.reduce(0) { max($0, abs($1)) }
        print("📊 Enrollment: Audio max amplitude: \(maxAmp)")
        if maxAmp < 0.005 { // Increased threshold slightly
             print("❌ Enrollment: Silence detected (Max Amp: \(maxAmp))")
             let alert = NSAlert()
             alert.messageText = L10n.isFrench ? "Aucun son détecté" : "No Audio Detected"
             alert.informativeText = L10n.isFrench ? "Le volume est trop bas ou le micro est muet. Veuillez vérifier vos réglages." : "Volume too low or microphone muted. Please check settings."
             alert.runModal()
             self.showEnrollmentRecorder(name: name, role: role, group: group)
             return
        }
        
        Task { @MainActor in
            do {
                let profile = try await SpeakerEnrollmentManager.shared.enrollSpeaker(
                    name: name,
                    role: role,
                    groupName: group,
                    audioSamples: buffer
                )
                print("✅ Enrollment: Successfully enrolled '\(profile.name)' with \(buffer.count) samples")
                self.refreshSpeakerDirectory()
                
                let alert = NSAlert()
                alert.messageText = L10n.isFrench ? "✅ Enregistrement réussi" : "✅ Enrollment Successful"
                alert.informativeText = L10n.isFrench ? "\(name) a été enregistré avec succès." : "\(name) has been enrolled successfully."
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = L10n.isFrench ? "Échec de l'enregistrement" : "Enrollment Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
    
    private func saveAudioToWav(buffer: [Float], url: URL) {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(buffer.count)
        if let data = pcmBuffer.floatChannelData {
            data[0].assign(from: buffer, count: buffer.count)
        }
        
        do {
            let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            try audioFile.write(from: pcmBuffer)
            print("💾 Debug Audio saved to: \(url.path)")
        } catch {
            print("❌ Failed to save debug audio: \(error)")
        }
    }
    
    // MARK: - Meetings Data
    
    @objc private func loadMeetings() {
        self.meetingsData = MeetingHistoryManager.shared.loadAllMeetings()
        meetingsTableView.reloadData()
        
        if let empty = meetingsEmptyStateView {
            empty.isHidden = !meetingsData.isEmpty
        }
        meetingsTableView.enclosingScrollView?.isHidden = meetingsData.isEmpty
    }
    
    @objc private func viewSelectedMeetingReport() {
        let row = meetingsTableView.selectedRow
        guard row >= 0 && row < meetingsData.count else { return }
        let meeting = meetingsData[row]
        
        activeReportWindow?.close()
        
        let reportWindow = MeetingDetailWindow(meeting: meeting)
        reportWindow.isReleasedWhenClosed = false
        reportWindow.makeKeyAndOrderFront(nil)
        
        self.activeReportWindow = reportWindow
    }
    
    @objc private func exportSelectedMeeting() {
        let row = meetingsTableView.selectedRow
        guard row >= 0 && row < meetingsData.count else { return }
        let meeting = meetingsData[row]
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "\(meeting.title).txt"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? meeting.finalTranscript.write(to: url, atomically: true, encoding: .utf8)
            }
        }
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
    
    func saveVocabularyData() {
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
        showInDockToggle.state = settings.showInDock ? .on : .off
        
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
        
        // Load existing key and update model info
        switch provider {
        case .google:
            apiKeyField.stringValue = SettingsManager.shared.geminiApiKey
            let modelId = SettingsManager.shared.geminiModelId
            let displayName = Constants.GeminiModel.allModels.first(where: { $0.id == modelId })?.displayName ?? modelId
            cloudModelLabel.stringValue = "Model: \(displayName)"
        case .openai:
            apiKeyField.stringValue = SettingsManager.shared.openaiApiKey
            let modelId = SettingsManager.shared.openaiModelId
            let displayName = Constants.OpenAIModel.allModels.first(where: { $0.id == modelId })?.displayName ?? modelId
            cloudModelLabel.stringValue = "Model: \(displayName)"
        case .anthropic:
            apiKeyField.stringValue = SettingsManager.shared.anthropicApiKey
            let modelId = SettingsManager.shared.anthropicModelId
            let displayName = Constants.AnthropicModel.allModels.first(where: { $0.id == modelId })?.displayName ?? modelId
            cloudModelLabel.stringValue = "Model: \(displayName)"
        case .none:
            apiKeyField.stringValue = ""
            cloudModelLabel.stringValue = ""
        }
        
        // Clear indicator on change
        statusIndicator.isHidden = true
        
        // Show/hide model selectors
        geminiModelBox.isHidden = (provider != .google)
        openaiModelBox.isHidden = (provider != .openai)
        anthropicModelBox.isHidden = (provider != .anthropic)
        
        // Trigger validation if key is not empty
        validateCurrentKey()
    }
    
    @objc private func geminiModelChanged(_ sender: NSPopUpButton) {
        guard let modelId = sender.selectedItem?.representedObject as? String else { return }
        SettingsManager.shared.geminiModelId = modelId
        
        let displayName = Constants.GeminiModel.allModels.first(where: { $0.id == modelId })?.displayName ?? modelId
        cloudModelLabel.stringValue = "Model: \(displayName)"
        validateCurrentKey()
    }
    
    @objc private func openaiModelChanged(_ sender: NSPopUpButton) {
        guard let modelId = sender.selectedItem?.representedObject as? String else { return }
        SettingsManager.shared.openaiModelId = modelId
        
        let displayName = Constants.OpenAIModel.allModels.first(where: { $0.id == modelId })?.displayName ?? modelId
        cloudModelLabel.stringValue = "Model: \(displayName)"
        validateCurrentKey()
    }
    
    @objc private func anthropicModelChanged(_ sender: NSPopUpButton) {
        guard let modelId = sender.selectedItem?.representedObject as? String else { return }
        SettingsManager.shared.anthropicModelId = modelId
        
        let displayName = Constants.AnthropicModel.allModels.first(where: { $0.id == modelId })?.displayName ?? modelId
        cloudModelLabel.stringValue = "Model: \(displayName)"
        validateCurrentKey()
    }
    
    @objc func showInDockChanged(_ sender: NSSwitch) {
        SettingsManager.shared.showInDock = (sender.state == .on)
    }

    func apiKeyChanged(to newValue: String) {
        let provider = SettingsManager.shared.llmProvider
        switch provider {
        case .google: SettingsManager.shared.geminiApiKey = newValue
        case .openai: SettingsManager.shared.openaiApiKey = newValue
        case .anthropic: SettingsManager.shared.anthropicApiKey = newValue
        case .none: break
        }
        
        // Debounce validation
        validationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.validateCurrentKey()
        }
        validationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    @objc func validateCurrentKey() {
        let provider = SettingsManager.shared.llmProvider
        let key = apiKeyField.stringValue
        
        statusIndicator.isHidden = false
        if provider == .none {
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
                let (isValid, modelName) = try await LLMManager.shared.validateApiKey(provider: provider, apiKey: key)
                DispatchQueue.main.async { [weak self] in
                    if isValid {
                        self?.statusIndicator.contentTintColor = .systemGreen
                        self?.statusIndicator.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Valid")
                        
                        if let modelName = modelName {
                            self?.cloudModelLabel.stringValue = "Model: \(modelName)"
                        }
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
        let isNone = (provider == .none)
        apiKeyStack.isHidden = isNone
        localModelLabel.isHidden = true // Local is removed
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
        
        // Temporarily switch to regular activation policy to allow keyboard input
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        
        // Activate app first, then show window
        NSApp.activate(ignoringOtherApps: true)
        
        // Use a slight delay to ensure activation completes before showing window
        DispatchQueue.main.async {
            self.level = .floating
            self.makeKeyAndOrderFront(nil)
            self.orderFrontRegardless()
            
            // Reset to normal level after bringing to front
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.level = .normal
            }
        }
        
        // Restore accessory policy when window closes if needed
        if previousPolicy == .accessory {
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: self, queue: .main) { [weak self] _ in
                guard self != nil else { return }
                if !SettingsManager.shared.showInDock {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
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
            return vocabularyData.count
        }
        if tableView == meetingsTableView {
            return meetingsData.count
        }
        return historyData.count
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView == vocabularyTableView {
            return 44
        }
        if tableView == meetingsTableView {
            return 60
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
                self?.saveVocabularyData()
            }
            
            view.onSave = { [weak self] newSpoken, newCorrected in
                guard let self = self else { return }
                guard row < self.vocabularyData.count else { return }
                
                self.vocabularyData[row] = (spoken: newSpoken, corrected: newCorrected)
                self.saveVocabularyData()
            }
            
            return view
        }
        
        if tableView == meetingsTableView {
            guard row < meetingsData.count else { return nil }
            let meeting = meetingsData[row]
            
            let id = NSUserInterfaceItemIdentifier("MeetingRow")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? MeetingRowView ?? MeetingRowView()
            cell.identifier = id
            cell.configure(meeting: meeting)
            return cell
        }
        
        // Default: History Table
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
        case .meetings: iconBg.layer?.backgroundColor = NSColor.systemTeal.cgColor
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
        descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        let stack = NSStackView(views: [iconView, titleLabel, descLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            bgView.topAnchor.constraint(equalTo: topAnchor),
            bgView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bgView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bgView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20),
            
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
            apiKeyChanged(to: textField.stringValue)
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
        
        // saveVocabulary() - removed as it's out of scope here
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
    private var triggerPillLabel: NSTextField!
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
    
    private func updateCardBackground() {
        let skillColor = colors[skill.color] ?? .systemBlue
        if isExpanded {
            layer?.backgroundColor = skillColor.withAlphaComponent(0.12).cgColor
            layer?.borderColor = skillColor.withAlphaComponent(0.3).cgColor
        } else {
            layer?.backgroundColor = skillColor.withAlphaComponent(0.06).cgColor
            layer?.borderColor = skillColor.withAlphaComponent(0.15).cgColor
        }
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        updateCardBackground()
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        
        // ━━━━ 1. HEADER ROW (Always Visible) ━━━━
        headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10
        headerRow.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 12)
        
        // Chevron
        chevronBtn = NSButton(title: "", target: self, action: #selector(toggleExpand))
        chevronBtn.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Expand")
        chevronBtn.isBordered = false
        chevronBtn.bezelStyle = .recessed
        chevronBtn.contentTintColor = .tertiaryLabelColor
        
        // Color dot
        colorIndicator = NSView()
        colorIndicator.translatesAutoresizingMaskIntoConstraints = false
        colorIndicator.wantsLayer = true
        colorIndicator.layer?.cornerRadius = 5
        colorIndicator.layer?.backgroundColor = colors[skill.color]?.cgColor ?? NSColor.systemBlue.cgColor
        
        // Name label
        nameLabel = NSTextField(labelWithString: skill.name)
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        // Trigger pill badge
        let triggerPill = NSView()
        triggerPill.translatesAutoresizingMaskIntoConstraints = false
        triggerPill.wantsLayer = true
        triggerPill.layer?.cornerRadius = 10
        triggerPill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        
        triggerPillLabel = NSTextField(labelWithString: "\u{1F3A4} \(skill.trigger)")
        triggerPillLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        triggerPillLabel.textColor = .controlAccentColor
        triggerPillLabel.translatesAutoresizingMaskIntoConstraints = false
        triggerPill.addSubview(triggerPillLabel)
        
        NSLayoutConstraint.activate([
            triggerPillLabel.leadingAnchor.constraint(equalTo: triggerPill.leadingAnchor, constant: 8),
            triggerPillLabel.trailingAnchor.constraint(equalTo: triggerPill.trailingAnchor, constant: -8),
            triggerPillLabel.topAnchor.constraint(equalTo: triggerPill.topAnchor, constant: 3),
            triggerPillLabel.bottomAnchor.constraint(equalTo: triggerPill.bottomAnchor, constant: -3),
        ])
        
        // Delete button
        let deleteBtn = NSButton(title: "", target: self, action: #selector(deleteSelf))
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteBtn.isBordered = false
        deleteBtn.bezelStyle = .recessed
        deleteBtn.contentTintColor = .systemRed.withAlphaComponent(0.5)
        
        headerRow.addArrangedSubview(chevronBtn)
        headerRow.addArrangedSubview(colorIndicator)
        headerRow.addArrangedSubview(nameLabel)
        headerRow.addArrangedSubview(triggerPill)
        headerRow.addArrangedSubview(NSView()) // Spacer
        headerRow.addArrangedSubview(deleteBtn)
        
        NSLayoutConstraint.activate([
            colorIndicator.widthAnchor.constraint(equalToConstant: 10),
            colorIndicator.heightAnchor.constraint(equalToConstant: 10),
        ])
        
        mainStack.addArrangedSubview(headerRow)
        
        // ━━━━ 2. EXPANDED EDITOR (Hidden by default) ━━━━
        promptContainer = NSView()
        promptContainer.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.isHidden = true
        
        let detailStack = NSStackView()
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 14
        detailStack.edgeInsets = NSEdgeInsets(top: 4, left: 40, bottom: 16, right: 14)
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        
        // ── Separator line
        let separator = NSBox()
        separator.boxType = .separator
        separator.alphaValue = 0.3
        separator.translatesAutoresizingMaskIntoConstraints = false
        detailStack.addArrangedSubview(separator)
        
        // ── Fields Row: Name, Trigger, Color
        let fieldsRow = NSStackView()
        fieldsRow.spacing = 12
        fieldsRow.distribution = .fill
        
        // Name Field
        let nameStack = NSStackView()
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 4
        let nameFieldLabel = NSTextField(labelWithString: L10n.isFrench ? "Nom de la compétence" : "Skill Name")
        nameFieldLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameFieldLabel.textColor = .tertiaryLabelColor
        nameField = NSTextField()
        nameField.stringValue = skill.name
        nameField.placeholderString = L10n.isFrench ? "Ex: Traducteur" : "Ex: Translator"
        nameField.bezelStyle = .roundedBezel
        nameField.delegate = self
        nameField.font = NSFont.systemFont(ofSize: 13)
        nameStack.addArrangedSubview(nameFieldLabel)
        nameStack.addArrangedSubview(nameField)
        
        // Trigger Field
        let triggerStack = NSStackView()
        triggerStack.orientation = .vertical
        triggerStack.alignment = .leading
        triggerStack.spacing = 4
        let triggerFieldLabel = NSTextField(labelWithString: L10n.isFrench ? "Mot déclencheur (vocal)" : "Trigger word (voice)")
        triggerFieldLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        triggerFieldLabel.textColor = .tertiaryLabelColor
        triggerField = NSTextField()
        triggerField.stringValue = skill.trigger
        triggerField.placeholderString = L10n.isFrench ? "Ex: assistant" : "Ex: assistant"
        triggerField.bezelStyle = .roundedBezel
        triggerField.delegate = self
        triggerField.font = NSFont.systemFont(ofSize: 13)
        triggerStack.addArrangedSubview(triggerFieldLabel)
        triggerStack.addArrangedSubview(triggerField)
        
        // Color Picker
        let colorStack = NSStackView()
        colorStack.orientation = .vertical
        colorStack.alignment = .leading
        colorStack.spacing = 4
        let colorFieldLabel = NSTextField(labelWithString: L10n.isFrench ? "Couleur" : "Color")
        colorFieldLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        colorFieldLabel.textColor = .tertiaryLabelColor
        colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (name, _) in colors {
            colorPopup.addItem(withTitle: name.capitalized)
            colorPopup.lastItem?.representedObject = name
        }
        colorPopup.selectItem(withTitle: skill.color.capitalized)
        colorPopup.target = self
        colorPopup.action = #selector(colorChanged(_:))
        colorStack.addArrangedSubview(colorFieldLabel)
        colorStack.addArrangedSubview(colorPopup)
        
        fieldsRow.addArrangedSubview(nameStack)
        fieldsRow.addArrangedSubview(triggerStack)
        fieldsRow.addArrangedSubview(colorStack)
        detailStack.addArrangedSubview(fieldsRow)
        
        // ── Prompt Editor
        let promptHeaderStack = NSStackView()
        promptHeaderStack.orientation = .horizontal
        promptHeaderStack.spacing = 6
        let promptIcon = NSTextField(labelWithString: "\u{1F4DD}")
        promptIcon.font = NSFont.systemFont(ofSize: 12)
        let promptLabel = NSTextField(labelWithString: L10n.isFrench ? "Instructions (pré-prompt envoyé à l'IA)" : "Instructions (pre-prompt sent to AI)")
        promptLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        promptLabel.textColor = .tertiaryLabelColor
        promptHeaderStack.addArrangedSubview(promptIcon)
        promptHeaderStack.addArrangedSubview(promptLabel)
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        
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
        promptTextView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.3)
        promptTextView.delegate = self
        promptTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        promptTextView.textContainerInset = NSSize(width: 10, height: 10)
        promptTextView.textColor = .labelColor
        promptTextView.isVerticallyResizable = true
        promptTextView.isHorizontallyResizable = false
        promptTextView.autoresizingMask = [.width]
        promptTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        promptTextView.minSize = NSSize(width: 0, height: 100)
        
        scrollView.documentView = promptTextView
        
        detailStack.addArrangedSubview(promptHeaderStack)
        detailStack.addArrangedSubview(scrollView)
        
        // ── Close/fold button
        let closeBtn = NSButton(title: L10n.isFrench ? "▲ Replier" : "▲ Collapse", target: self, action: #selector(toggleExpand))
        closeBtn.bezelStyle = .recessed
        closeBtn.isBordered = false
        closeBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        closeBtn.contentTintColor = .secondaryLabelColor
        detailStack.addArrangedSubview(closeBtn)
        
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 100),
            scrollView.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -54),
            nameField.widthAnchor.constraint(equalToConstant: 160),
            triggerField.widthAnchor.constraint(equalToConstant: 160),
            colorPopup.widthAnchor.constraint(equalToConstant: 90),
            separator.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -54),
        ])
        
        promptContainer.addSubview(detailStack)
        NSLayoutConstraint.activate([
            detailStack.topAnchor.constraint(equalTo: promptContainer.topAnchor),
            detailStack.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor),
            detailStack.bottomAnchor.constraint(equalTo: promptContainer.bottomAnchor),
        ])
        
        mainStack.addArrangedSubview(promptContainer)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    @objc private func toggleExpand() {
        isExpanded.toggle()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            promptContainer.isHidden = !isExpanded
            chevronBtn.image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
            updateCardBackground()
        }
    }
    
    @objc private func deleteSelf() {
        onDelete?(index)
    }
    
    @objc private func colorChanged(_ sender: NSPopUpButton) {
        if let colorName = sender.selectedItem?.representedObject as? String {
            skill.color = colorName
            colorIndicator.layer?.backgroundColor = colors[colorName]?.cgColor
            updateCardBackground()
            onUpdate?(index, skill)
        }
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
            let skillColor = colors[skill.color] ?? .systemBlue
            layer?.backgroundColor = skillColor.withAlphaComponent(0.12).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if !isExpanded {
            updateCardBackground()
        }
    }
    
    // MARK: - Delegates
    func controlTextDidChange(_ obj: Notification) {
        skill.name = nameField.stringValue
        skill.trigger = triggerField.stringValue
        nameLabel.stringValue = skill.name
        triggerPillLabel.stringValue = "\u{1F3A4} \(skill.trigger)"
        onUpdate?(index, skill)
    }
    
    func textDidChange(_ notification: Notification) {
        skill.prompt = promptTextView.string
        onUpdate?(index, skill)
    }
}

