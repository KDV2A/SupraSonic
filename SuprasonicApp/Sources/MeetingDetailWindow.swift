import Cocoa
import AVFoundation
import UniformTypeIdentifiers

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
    private var sidebarContainer: NSView?
    
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
        self.sidebarContainer = sidebar
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
        
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 50),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])
        
        // --- Header ---
        if MeetingManager.shared.isMeetingActive && MeetingManager.shared.currentMeeting?.id == meeting.id {
            stack.addArrangedSubview(createLiveTag())
        }
        
        let titleLabel = NSTextField(wrappingLabelWithString: meeting.title)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .labelColor
        stack.addArrangedSubview(titleLabel)
        
        let dateLabel = NSTextField(labelWithString: meeting.date.formatted(date: .long, time: .shortened))
        dateLabel.font = NSFont.systemFont(ofSize: 13)
        dateLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(dateLabel)
        
        if meeting.duration > 0 {
            let durMin = Int(meeting.duration) / 60
            let durSec = Int(meeting.duration) % 60
            let durStr = durMin > 0 ? "\(durMin) min \(durSec)s" : "\(durSec)s"
            let durLabel = NSTextField(labelWithString: L10n.isFrench ? "Durée : \(durStr)" : "Duration: \(durStr)")
            durLabel.font = NSFont.systemFont(ofSize: 12)
            durLabel.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(durLabel)
        }
        
        // --- Summary ---
        if let summary = meeting.summary, !summary.isEmpty {
            stack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "RÉSUMÉ" : "SUMMARY"))
            let summaryText = NSTextField(wrappingLabelWithString: summary)
            summaryText.font = NSFont.systemFont(ofSize: 13)
            summaryText.lineBreakMode = .byWordWrapping
            summaryText.textColor = .labelColor
            stack.addArrangedSubview(summaryText)
        }
        
        // --- Participants ---
        stack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "PARTICIPANTS" : "PARTICIPANTS"))
        participantsStack = NSStackView()
        participantsStack.orientation = .vertical
        participantsStack.spacing = 8
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
        
        // --- Export Button ---
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)
        
        let exportButton = NSButton(title: L10n.isFrench ? "Exporter le compte-rendu" : "Export Summary", target: self, action: #selector(exportMeetingSummary))
        exportButton.bezelStyle = .rounded
        exportButton.controlSize = .large
        exportButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Export")
        exportButton.imagePosition = .imageLeading
        stack.addArrangedSubview(exportButton)
        
        return container
    }
    
    @objc private func exportMeetingSummary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(meeting.title.replacingOccurrences(of: " ", with: "_")).txt"
        panel.title = L10n.isFrench ? "Exporter le compte-rendu" : "Export Meeting Summary"
        
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            
            var content = ""
            
            // Title & Date
            content += "═══════════════════════════════════════\n"
            content += "  \(self.meeting.title)\n"
            content += "  \(self.meeting.date.formatted(date: .long, time: .shortened))\n"
            if self.meeting.duration > 0 {
                let m = Int(self.meeting.duration) / 60
                let s = Int(self.meeting.duration) % 60
                content += "  \(L10n.isFrench ? "Durée" : "Duration"): \(m > 0 ? "\(m) min \(s)s" : "\(s)s")\n"
            }
            content += "═══════════════════════════════════════\n\n"
            
            // Summary
            if let summary = self.meeting.summary, !summary.isEmpty {
                content += "── \(L10n.isFrench ? "RÉSUMÉ" : "SUMMARY") ──\n\n"
                content += summary + "\n\n"
            }
            
            // Action Items
            if !self.meeting.actionItems.isEmpty {
                content += "── \(L10n.isFrench ? "ACTIONS" : "ACTION ITEMS") ──\n\n"
                for item in self.meeting.actionItems {
                    content += "  • \(item)\n"
                }
                content += "\n"
            }
            
            // Transcription
            content += "── TRANSCRIPTION ──\n\n"
            for segment in self.meeting.segments {
                let name = segment.speakerName ?? "Participant"
                let h = Int(segment.timestamp) / 3600
                let m = (Int(segment.timestamp) % 3600) / 60
                let s = Int(segment.timestamp) % 60
                let ts = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
                content += "[\(ts)] \(name):\n\(segment.text)\n\n"
            }
            
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            } catch {
                debugLog("❌ Export failed: \(error)")
            }
        }
    }
    
    private func createMainContent() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Hidden audio controls (only shown for legacy recordings)
        playButton = NSButton()
        playButton.isHidden = true
        timeSlider = NSSlider()
        timeSlider.isHidden = true
        timeLabel = NSTextField(labelWithString: "")
        timeLabel.isHidden = true
        
        // Transcript header
        let headerBar = NSView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.wantsLayer = true
        
        let transcriptTitle = NSTextField(labelWithString: L10n.isFrench ? "TRANSCRIPTION" : "TRANSCRIPT")
        transcriptTitle.translatesAutoresizingMaskIntoConstraints = false
        transcriptTitle.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        transcriptTitle.textColor = .tertiaryLabelColor
        headerBar.addSubview(transcriptTitle)
        
        let segmentCount = NSTextField(labelWithString: "\(meeting.segments.count) \(L10n.isFrench ? "segments" : "segments")")
        segmentCount.translatesAutoresizingMaskIntoConstraints = false
        segmentCount.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        segmentCount.textColor = .quaternaryLabelColor
        headerBar.addSubview(segmentCount)
        
        NSLayoutConstraint.activate([
            transcriptTitle.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 24),
            transcriptTitle.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            segmentCount.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -24),
            segmentCount.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor)
        ])
        
        // Transcript Table
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 20, right: 0)
        
        transcriptTableView = NSTableView()
        transcriptTableView.delegate = self
        transcriptTableView.dataSource = self
        transcriptTableView.backgroundColor = .clear
        transcriptTableView.headerView = nil
        transcriptTableView.intercellSpacing = NSSize(width: 0, height: 4)
        transcriptTableView.selectionHighlightStyle = .none
        transcriptTableView.usesAutomaticRowHeights = true
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainCol"))
        col.resizingMask = .autoresizingMask
        transcriptTableView.addTableColumn(col)
        
        scroll.documentView = transcriptTableView
        
        container.addSubview(headerBar)
        container.addSubview(scroll)
        
        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            headerBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 30),
            
            scroll.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 4),
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
    
    private func rebuildSidebar() {
        guard let container = sidebarContainer else { return }
        // Remove old content
        container.subviews.forEach { $0.removeFromSuperview() }
        
        // Rebuild sidebar with updated meeting data (summary, action items, etc.)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 50),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])
        
        // Header
        let titleLabel = NSTextField(wrappingLabelWithString: meeting.title)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .labelColor
        stack.addArrangedSubview(titleLabel)
        
        let dateLabel = NSTextField(labelWithString: meeting.date.formatted(date: .long, time: .shortened))
        dateLabel.font = NSFont.systemFont(ofSize: 13)
        dateLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(dateLabel)
        
        if meeting.duration > 0 {
            let durMin = Int(meeting.duration) / 60
            let durSec = Int(meeting.duration) % 60
            let durStr = durMin > 0 ? "\(durMin) min \(durSec)s" : "\(durSec)s"
            let durLabel = NSTextField(labelWithString: L10n.isFrench ? "Durée : \(durStr)" : "Duration: \(durStr)")
            durLabel.font = NSFont.systemFont(ofSize: 12)
            durLabel.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(durLabel)
        }
        
        // Summary
        if let summary = meeting.summary, !summary.isEmpty {
            stack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "RÉSUMÉ" : "SUMMARY"))
            let summaryText = NSTextField(wrappingLabelWithString: summary)
            summaryText.font = NSFont.systemFont(ofSize: 13)
            summaryText.lineBreakMode = .byWordWrapping
            summaryText.textColor = .labelColor
            stack.addArrangedSubview(summaryText)
        }
        
        // Participants
        stack.addArrangedSubview(createSectionHeader(L10n.isFrench ? "PARTICIPANTS" : "PARTICIPANTS"))
        participantsStack = NSStackView()
        participantsStack.orientation = .vertical
        participantsStack.spacing = 8
        participantsStack.alignment = .leading
        stack.addArrangedSubview(participantsStack)
        refreshParticipants()
        
        // Action Items
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
        
        // Export Button
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)
        
        let exportButton = NSButton(title: L10n.isFrench ? "Exporter le compte-rendu" : "Export Summary", target: self, action: #selector(exportMeetingSummary))
        exportButton.bezelStyle = .rounded
        exportButton.controlSize = .large
        exportButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Export")
        exportButton.imagePosition = .imageLeading
        stack.addArrangedSubview(exportButton)
    }
    
    private func refreshParticipants() {
        participantsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Resolve participant IDs to SpeakerProfiles
        let profiles = meeting.participantIds.compactMap { id in
            SpeakerEnrollmentManager.shared.profiles.first { $0.id == id }
        }
        
        if profiles.isEmpty {
            // Show unique speaker names from segments instead
            let speakerNames = Set(meeting.segments.compactMap { $0.speakerName }).sorted()
            if speakerNames.isEmpty {
                let label = NSTextField(labelWithString: L10n.isFrench ? "Aucun participant détecté" : "No participants detected")
                label.font = NSFont.systemFont(ofSize: 12)
                label.textColor = .tertiaryLabelColor
                participantsStack.addArrangedSubview(label)
            } else {
                for name in speakerNames {
                    let label = NSTextField(labelWithString: name)
                    label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
                    label.textColor = .secondaryLabelColor
                    participantsStack.addArrangedSubview(label)
                }
            }
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
        // Check if meeting completed (AI summary ready) — reload from disk
        if let info = notification.userInfo,
           let completed = info["meetingCompleted"] as? Bool, completed,
           let meetingIdStr = info["meetingId"] as? String,
           meetingIdStr == meeting.id.uuidString {
            let updated = MeetingHistoryManager.shared.loadAllMeetings().first { $0.id == self.meeting.id }
            if let updated = updated {
                self.meeting = updated
                DispatchQueue.main.async {
                    // Rebuild sidebar to show summary & action items
                    self.rebuildSidebar()
                    self.transcriptTableView.reloadData()
                    self.refreshParticipants()
                }
            }
            return
        }
        
        // Live updates during recording
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
        // Audio playback disabled - audio files are no longer stored
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
        
        cell?.configure(segment: segment, meetingDate: meeting.date, tableWidth: tableView.frame.width)
        return cell
    }
    
}

// MARK: - Modern Transcript Cell
class TranscriptCellView: NSTableCellView {
    private var timeLabel: NSTextField!
    private var speakerLabel: NSTextField!
    private var contentLabel: NSTextField!
    private var headerRow: NSStackView!
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setup() {
        timeLabel = NSTextField(labelWithString: "")
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        speakerLabel = NSTextField(labelWithString: "")
        speakerLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        speakerLabel.textColor = Constants.brandBlue
        speakerLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentLabel = NSTextField(wrappingLabelWithString: "")
        contentLabel.font = NSFont.systemFont(ofSize: 14)
        contentLabel.textColor = .labelColor
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.usesSingleLineMode = false
        contentLabel.maximumNumberOfLines = 0
        contentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        headerRow = NSStackView(views: [timeLabel, speakerLabel])
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.spacing = 10
        headerRow.alignment = .firstBaseline
        
        addSubview(headerRow)
        addSubview(contentLabel)
        
        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            headerRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            
            contentLabel.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 4),
            contentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            contentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }
    
    func configure(segment: MeetingSegment, meetingDate: Date, tableWidth: CGFloat = 600) {
        // Show actual clock time (meetingDate + elapsed seconds)
        let segmentDate = meetingDate.addingTimeInterval(segment.timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        timeLabel.stringValue = formatter.string(from: segmentDate)
        
        speakerLabel.stringValue = segment.speakerName ?? "Participant"
        contentLabel.stringValue = segment.text
        contentLabel.preferredMaxLayoutWidth = max(200, tableWidth - 48)
        
        // Color speaker name based on profile
        if let profile = SpeakerEnrollmentManager.shared.profiles.first(where: { $0.name == segment.speakerName }) {
            speakerLabel.textColor = NSColor(hex: profile.colorHex) ?? Constants.brandBlue
        } else {
            speakerLabel.textColor = Constants.brandBlue
        }
    }
}

// Color Hex Helper
