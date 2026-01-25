import Cocoa
import Carbon.HIToolbox
import AVFoundation

class SettingsWindow: NSWindow {
    private var tabView: NSTabView!
    private var configTab: NSTabViewItem!
    private var historyTab: NSTabViewItem!
    
    // Configuration controls
    private var historyToggle: NSSwitch!
    private var launchOnLoginToggle: NSSwitch!
    private var microphonePopup: NSPopUpButton!
    private var pttCard: ModeCardView!
    private var toggleCard: ModeCardView!
    private var hotkeyButton: HotkeyButton!
    
    // Model controls (simplified for FluidAudio)
    private var languagePopup: NSPopUpButton!
    
    // History controls
    private var historyTableView: NSTableView!
    private var historyScrollView: NSScrollView!
    private var historyData: [TranscriptionEntry] = []
    
    private let l = L10n.current
    
    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 850, height: 600)
        
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = l.settingsTitle
        self.center()
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 600, height: 500)
        
        setupUI()
        loadSettings()
        
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
        let contentView = NSView()
        self.contentView = contentView
        
        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        
        configTab = NSTabViewItem(identifier: "config")
        configTab.label = l.configurationTab
        configTab.view = createConfigView()
        tabView.addTabViewItem(configTab)
        
        historyTab = NSTabViewItem(identifier: "history")
        historyTab.label = l.historyTab
        historyTab.view = createHistoryView()
        tabView.addTabViewItem(historyTab)
        
        contentView.addSubview(tabView)
        
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func createConfigView() -> NSView {
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
        mainStack.spacing = 30
        mainStack.edgeInsets = NSEdgeInsets(top: 30, left: 40, bottom: 40, right: 40)
        
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
        
        // Microphone Section
        mainStack.addArrangedSubview(createSectionHeader(l.microphone))
        let microRow = createSettingRow(
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
        mainStack.addArrangedSubview(microRow)
        
        mainStack.addArrangedSubview(createSeparator())
        
        // Version info at the bottom
        let versionStack = NSStackView()
        versionStack.orientation = .horizontal
        versionStack.spacing = 4
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        
        let versionLabel = NSTextField(labelWithString: "SupraSonic v\(version)")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        
        versionStack.addArrangedSubview(versionLabel)
        mainStack.addArrangedSubview(versionStack)
        
        mainStack.addArrangedSubview(createSeparator())
        
        // Shortcuts Section
        mainStack.addArrangedSubview(createSectionHeader(l.shortcutsSection))
        
        let cardsStack = NSStackView()
        cardsStack.translatesAutoresizingMaskIntoConstraints = false
        cardsStack.orientation = .horizontal
        cardsStack.distribution = .fillEqually
        cardsStack.spacing = 16
        
        pttCard = ModeCardView(
            title: l.hotkeyModePTT,
            description: l.pushToTalkDesc,
            iconName: "mic.fill",
            mode: .pushToTalk
        )
        pttCard.target = self
        pttCard.action = #selector(hotkeyModeCardSelected(_:))
        
        toggleCard = ModeCardView(
            title: l.hotkeyModeToggle,
            description: l.recordToggleDesc,
            iconName: "record.circle",
            mode: .toggle
        )
        toggleCard.target = self
        toggleCard.action = #selector(hotkeyModeCardSelected(_:))
        
        cardsStack.addArrangedSubview(pttCard)
        cardsStack.addArrangedSubview(toggleCard)
        
        let modeRow = createSettingRow(
            title: l.hotkeyModeLabel,
            description: "",
            control: cardsStack
        )
        mainStack.addArrangedSubview(modeRow)
        
        NSLayoutConstraint.activate([
            cardsStack.heightAnchor.constraint(equalToConstant: 160),
            cardsStack.widthAnchor.constraint(equalToConstant: 480)
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
        mainStack.addArrangedSubview(pttRow)
        
        mainStack.addArrangedSubview(createSeparator())
        
        // Options Section
        mainStack.addArrangedSubview(createSectionHeader(l.optionsSection))
        
        let historyRow = createSettingRow(
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
        )
        mainStack.addArrangedSubview(historyRow)
        
        let launchRow = createSettingRow(
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
        )
        mainStack.addArrangedSubview(launchRow)
        
        mainStack.addArrangedSubview(createSeparator())
        
        // Reset Button
        let resetBtn = NSButton(title: l.reset, target: self, action: #selector(resetSettings))
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 13)
        
        let resetContainer = NSStackView(views: [resetBtn])
        resetContainer.translatesAutoresizingMaskIntoConstraints = false
        resetContainer.edgeInsets = NSEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        mainStack.addArrangedSubview(resetContainer)
        
        return container
    }
    
    private func createSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = .secondaryLabelColor
        return label
    }
    
    private func createSeparator() -> NSView {
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        return separator
    }
    
    private func createSettingRow(title: String, description: String, control: NSView) -> NSView {
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
        
        container.addArrangedSubview(textStack)
        container.addArrangedSubview(control)
        
        NSLayoutConstraint.activate([
            textStack.widthAnchor.constraint(equalToConstant: 240),
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])
        
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
    
    
    private func createHistoryView() -> NSView {
        let container = NSView()
        
        let mainStack = NSStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 20
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 30, bottom: 20, right: 30)
        
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
            
            historyScrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -60),
            buttonStack.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        return container
    }
    
    private func loadSettings() {
        let settings = SettingsManager.shared
        
        // Load toggles
        historyToggle.state = settings.historyEnabled ? .on : .off
        launchOnLoginToggle.state = settings.launchOnLogin ? .on : .off
        
        // Load hotkey mode
        updateModeCards(settings.hotkeyMode)
        
        // Load hotkey button
        hotkeyButton.setHotkey(keyCode: settings.pushToTalkKey, 
                               modifiers: settings.pushToTalkModifiers,
                               keyString: settings.pushToTalkKeyString)
        
        // Load microphones and history
        loadMicrophones()
        reloadHistory()
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
        self.level = .floating
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
        return historyData.count
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < historyData.count else { return 80 }
        let text = historyData[row].text
        let baseHeight: CGFloat = 80
        let charsPerLine = 70
        let lines = max(1, (text.count / charsPerLine) + 1)
        return max(baseHeight, CGFloat(lines) * 20 + 50)
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
            cardView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor
            cardView.layer?.borderColor = NSColor(white: 0.22, alpha: 1.0).cgColor
        } else {
            cardView.layer?.backgroundColor = NSColor.white.cgColor
            cardView.layer?.borderColor = NSColor(white: 0.88, alpha: 1.0).cgColor
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
        self.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        self.title = L10n.current.clickToSet
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.setButtonType(.momentaryPushIn)
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
        
        // Notify the target that the hotkey changed
        DispatchQueue.main.async {
            self.sendAction(self.action, to: self.target)
        }
    }
    
    private func cancelRecording() {
        removeMonitors()
        isRecording = false
        updateTitle()
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

class ModeCardView: NSControl {
    let mode: SettingsManager.HotkeyMode
    private let titleLabel: NSTextField
    private let descLabel: NSTextField
    private let iconView: NSImageView
    
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
        
        super.init(frame: .zero)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 2
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        iconView.contentTintColor = .secondaryLabelColor
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .left
        
        let stack = NSStackView(views: [iconView, titleLabel, descLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconView.heightAnchor.constraint(equalToConstant: 24),
            iconView.widthAnchor.constraint(equalToConstant: 24)
        ])
        
        updateAppearance()
    }
    
    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            iconView.contentTintColor = .controlAccentColor
            titleLabel.textColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            iconView.contentTintColor = .secondaryLabelColor
            titleLabel.textColor = .secondaryLabelColor
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

