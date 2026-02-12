import Cocoa
import AVFoundation

class MeetingDetailWindow: NSWindow, NSSplitViewDelegate, NSTableViewDelegate, NSTableViewDataSource {
    private var meeting: Meeting
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    
    // UI Elements
    private var playButton: NSButton!
    private var timeSlider: NSSlider!
    private var timeLabel: NSTextField!
    private var transcriptTableView: NSTableView!
    private var participantsStack: NSStackView!
    private var liveIndicator: NSView?
    
    private var timeObserverToken: Any?
    
    init(meeting: Meeting) {
        self.meeting = meeting
        
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        let rect = NSRect(x: 0, y: 0, width: 1100, height: 800)
        
        super.init(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        
        self.title = meeting.title
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = .windowBackgroundColor
        
        setupUI()
        setupAudio()
        refreshParticipants()
        
        self.center()
        
        // Listen for live updates
        NotificationCenter.default.addObserver(self, selector: #selector(onTranscriptUpdated), name: Constants.NotificationNames.meetingTranscriptUpdated, object: nil)
    }
    
    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .sidebar
        self.contentView = visualEffect
        
        // Main Split View
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(splitView)
        
        // 1. Sidebar (AI Summary & Participants)
        let sidebar = createSidebar()
        splitView.addArrangedSubview(sidebar)
        
        // 2. Main Content (Player & Transcript)
        let mainContent = createMainContent()
        splitView.addArrangedSubview(mainContent)
        
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
        ])
    }
    
    private func createSidebar() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        container.addSubview(scroll)
        
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 60, left: 24, bottom: 40, right: 24)
        document.addSubview(stack)
        
        // Constraints
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])
        
        // --- Header Section ---
        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 8
        
        if MeetingManager.shared.isMeetingActive && MeetingManager.shared.currentMeeting?.id == meeting.id {
            let liveTag = createLiveTag()
            headerStack.addArrangedSubview(liveTag)
        }
        
        let titleLabel = NSTextField(wrappingLabelWithString: meeting.title)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .labelColor
        headerStack.addArrangedSubview(titleLabel)
        
        let dateLabel = NSTextField(labelWithString: meeting.date.formatted(date: .long, time: .shortened))
        dateLabel.font = NSFont.systemFont(ofSize: 13)
        dateLabel.textColor = .secondaryLabelColor
        headerStack.addArrangedSubview(dateLabel)
        
        stack.addArrangedSubview(headerStack)
        
        // --- Summary Section ---
        if let summary = meeting.summary {
            stack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "RÉSUMÉ" : "SUMMARY"))
            let summaryText = NSTextField(wrappingLabelWithString: summary)
            summaryText.font = NSFont.systemFont(ofSize: 14)
            summaryText.lineBreakMode = .byWordWrapping
            stack.addArrangedSubview(summaryText)
        }
        
        // --- Participants Section ---
        stack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "PARTICIPANTS" : "PARTICIPANTS"))
        participantsStack = NSStackView()
        participantsStack.orientation = .vertical
        participantsStack.spacing = 12
        participantsStack.alignment = .leading
        stack.addArrangedSubview(participantsStack)
        
        // --- Action Items ---
        if !meeting.actionItems.isEmpty {
            stack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "ACTIONS" : "ACTION ITEMS"))
            for item in meeting.actionItems {
                let row = NSStackView()
                row.spacing = 8
                let dot = NSTextField(labelWithString: "•")
                dot.textColor = Constants.brandBlue
                let txt = NSTextField(wrappingLabelWithString: item)
                txt.font = NSFont.systemFont(ofSize: 13)
                row.addArrangedSubview(dot)
                row.addArrangedSubview(txt)
                stack.addArrangedSubview(row)
            }
        }
        
        return container
    }
    
    private func createMainContent() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // 1. Player Control Bar
        let playerBar = NSView()
        playerBar.translatesAutoresizingMaskIntoConstraints = false
        playerBar.wantsLayer = true
        playerBar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3).cgColor
        
        playButton = NSButton()
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.bezelStyle = .circular
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        playButton.isBordered = false
        playButton.contentTintColor = Constants.brandBlue
        playButton.target = self
        playButton.action = #selector(togglePlayback)
        
        timeSlider = NSSlider()
        timeSlider.translatesAutoresizingMaskIntoConstraints = false
        timeSlider.target = self
        timeSlider.action = #selector(sliderScrubbed)
        
        timeLabel = NSTextField(labelWithString: "00:00 / 00:00")
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .secondaryLabelColor
        
        playerBar.addSubview(playButton)
        playerBar.addSubview(timeSlider)
        playerBar.addSubview(timeLabel)
        
        NSLayoutConstraint.activate([
            playButton.leadingAnchor.constraint(equalTo: playerBar.leadingAnchor, constant: 20),
            playButton.centerYAnchor.constraint(equalTo: playerBar.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 36),
            playButton.heightAnchor.constraint(equalToConstant: 36),
            
            timeSlider.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 16),
            timeSlider.centerYAnchor.constraint(equalTo: playerBar.centerYAnchor),
            timeSlider.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -16),
            
            timeLabel.trailingAnchor.constraint(equalTo: playerBar.trailingAnchor, constant: -24),
            timeLabel.centerYAnchor.constraint(equalTo: playerBar.centerYAnchor)
        ])
        
        // 2. Transcript Table
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)
        
        transcriptTableView = NSTableView()
        transcriptTableView.delegate = self
        transcriptTableView.dataSource = self
        transcriptTableView.backgroundColor = .clear
        transcriptTableView.headerView = nil
        transcriptTableView.intercellSpacing = NSSize(width: 0, height: 16)
        transcriptTableView.selectionHighlightStyle = .none
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainCol"))
        col.resizingMask = .autoresizingMask
        transcriptTableView.addTableColumn(col)
        
        scroll.documentView = transcriptTableView
        
        container.addSubview(playerBar)
        container.addSubview(scroll)
        
        NSLayoutConstraint.activate([
            playerBar.topAnchor.constraint(equalTo: container.topAnchor),
            playerBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playerBar.heightAnchor.constraint(equalToConstant: 72),
            
            scroll.topAnchor.constraint(equalTo: playerBar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    // MARK: - Component Helpers
    
    private func createSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = .tertiaryLabelColor
        return label
    }
    
    private func createLiveTag() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.2).cgColor
        container.layer?.cornerRadius = 4
        
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        
        let label = NSTextField(labelWithString: "LIVE")
        label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(dot)
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 20),
            dot.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        // Pulsing animation
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        dot.layer?.add(animation, forKey: "pulse")
        
        self.liveIndicator = container
        return container
    }
    
    private func refreshParticipants() {
        participantsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Resolve participant IDs to SpeakerProfiles
        let profiles = meeting.participantIds.compactMap { id in
            SpeakerEnrollmentManager.shared.profiles.first { $0.id == id }
        }
        
        if profiles.isEmpty {
            let label = NSTextField(labelWithString: L10n.isFrench ? "Identification en cours..." : "Identifying participants...")
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.textColor = .secondaryLabelColor
            participantsStack.addArrangedSubview(label)
        } else {
            for profile in profiles {
                let row = createParticipantRow(profile: profile)
                participantsStack.addArrangedSubview(row)
            }
        }
    }
    
    private func createParticipantRow(profile: SpeakerProfile) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Avatar
        let avatar = NSView()
        avatar.wantsLayer = true
        avatar.layer?.backgroundColor = NSColor(hex: profile.colorHex)?.cgColor ?? NSColor.systemBlue.cgColor
        avatar.layer?.cornerRadius = 16
        avatar.translatesAutoresizingMaskIntoConstraints = false
        
        let initials = NSTextField(labelWithString: profile.initials)
        initials.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        initials.textColor = .white
        initials.alignment = .center
        initials.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(initials)
        
        // Info
        let name = NSTextField(labelWithString: profile.name)
        name.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let role = NSTextField(labelWithString: profile.role)
        role.font = NSFont.systemFont(ofSize: 11)
        role.textColor = .secondaryLabelColor
        
        let infoStack = NSStackView(views: [name, role])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 1
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(avatar)
        container.addSubview(infoStack)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 40),
            avatar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avatar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32),
            
            initials.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            initials.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            
            infoStack.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            infoStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            infoStack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        
        return container
    }
    
    // MARK: - Notification Handlers
    
    @objc private func onTranscriptUpdated(_ notification: Notification) {
        // Sync meeting state
        if let current = MeetingManager.shared.currentMeeting, current.id == meeting.id {
            self.meeting = current
            DispatchQueue.main.async {
                self.transcriptTableView.reloadData()
                self.refreshParticipants()
                
                // Auto-scroll to bottom if near
                let scroll = self.transcriptTableView.enclosingScrollView
                if let documentView = scroll?.documentView {
                    let rect = documentView.frame
                    self.transcriptTableView.scroll(NSPoint(x: 0, y: rect.height))
                }
            }
        }
    }
    
    // MARK: - Audio Logic
    
    private func setupAudio() {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let audioURL = documents.appendingPathComponent("SupraSonic/Meetings/\(meeting.id.uuidString)/recording.wav")
        
        if fileManager.fileExists(atPath: audioURL.path) {
            let item = AVPlayerItem(url: audioURL)
            self.playerItem = item
            self.player = AVPlayer(playerItem: item)
            
            // Observer duration
            Task {
                do {
                    let duration = try await item.asset.load(.duration)
                    let seconds = CMTimeGetSeconds(duration)
                    if !seconds.isNaN && seconds > 0 {
                        await MainActor.run {
                            self.timeSlider.maxValue = seconds
                            self.updateTimeLabel(manualCurrent: 0, duration: seconds)
                        }
                    }
                } catch {
                    print("⚠️ MeetingDetail: Failed to load duration: \(error)")
                }
            }
            
            // Periodic time observer
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                if self.player?.rate != 0 {
                    self.timeSlider.doubleValue = time.seconds
                    self.updateTimeLabel(manualCurrent: time.seconds)
                }
            }
            
            // End observer
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                self?.playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
                self?.player?.seek(to: .zero)
            }
        }
    }
    
    @objc private func togglePlayback() {
        guard let p = player else { return }
        if p.rate == 0 {
            p.play()
            playButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
        } else {
            p.pause()
            playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        }
    }
    
    @objc private func sliderScrubbed() {
        guard let p = player else { return }
        let targetTime = CMTime(seconds: timeSlider.doubleValue, preferredTimescale: 600)
        p.seek(to: targetTime)
        updateTimeLabel(manualCurrent: timeSlider.doubleValue)
    }
    
    private func updateTimeLabel(manualCurrent: Double? = nil, duration: Double? = nil) {
        let current = manualCurrent ?? player?.currentTime().seconds ?? 0
        let total = duration ?? timeSlider.maxValue
        let totalVal = total.isNaN ? 0 : total
        
        timeLabel.stringValue = "\(formatTime(current)) / \(formatTime(totalVal))"
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
    
    // MARK: - TableView (Transcript)
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return meeting.segments.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let segment = meeting.segments[row]
        let id = NSUserInterfaceItemIdentifier("TranscriptRow")
        
        var cell = tableView.makeView(withIdentifier: id, owner: self) as? TranscriptCellView
        if cell == nil {
            cell = TranscriptCellView()
            cell?.identifier = id
        }
        
        cell?.configure(segment: segment)
        return cell
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let segment = meeting.segments[row]
        let width = tableView.frame.width - 120 // Avatar + Spacing
        let height = segment.text.height(withConstrainedWidth: width, font: NSFont.systemFont(ofSize: 14))
        return max(60, height + 40)
    }
}

// MARK: - Modern Transcript Cell
class TranscriptCellView: NSTableCellView {
    private let avatarView = NSView()
    private let initialsLabel = NSTextField()
    private let timeLabel = NSTextField()
    private let speakerLabel = NSTextField()
    private let contentLabel = NSTextField()
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setup() {
        avatarView.wantsLayer = true
        avatarView.layer?.cornerRadius = 18
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        
        initialsLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        initialsLabel.textColor = .white
        initialsLabel.alignment = .center
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarView.addSubview(initialsLabel)
        
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        speakerLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        speakerLabel.textColor = .labelColor
        speakerLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentLabel.font = NSFont.systemFont(ofSize: 15)
        contentLabel.textColor = .labelColor
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.cell?.wraps = true
        contentLabel.cell?.isScrollable = false
        
        addSubview(avatarView)
        addSubview(timeLabel)
        addSubview(speakerLabel)
        addSubview(contentLabel)
        
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            avatarView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),
            
            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            
            speakerLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 16),
            speakerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            
            timeLabel.leadingAnchor.constraint(equalTo: speakerLabel.trailingAnchor, constant: 12),
            timeLabel.centerYAnchor.constraint(equalTo: speakerLabel.centerYAnchor),
            
            contentLabel.leadingAnchor.constraint(equalTo: speakerLabel.leadingAnchor),
            contentLabel.topAnchor.constraint(equalTo: speakerLabel.bottomAnchor, constant: 6),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            contentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }
    
    func configure(segment: MeetingSegment) {
        let timeStr = formatTime(segment.timestamp)
        timeLabel.stringValue = timeStr
        
        let speakerName = segment.speakerName ?? "Speaker"
        speakerLabel.stringValue = speakerName
        contentLabel.stringValue = segment.text
        
        // Match avatar colors
        if let profile = SpeakerEnrollmentManager.shared.profiles.first(where: { $0.name == speakerName }) {
             avatarView.layer?.backgroundColor = NSColor(hex: profile.colorHex)?.cgColor
             initialsLabel.stringValue = profile.initials
        } else {
             avatarView.layer?.backgroundColor = NSColor.systemGray.cgColor
             initialsLabel.stringValue = String(speakerName.prefix(1)).uppercased()
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// Color Hex Helper
