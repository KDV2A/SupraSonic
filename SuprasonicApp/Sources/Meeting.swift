import Foundation

// MARK: - Meeting Status

enum MeetingStatus: String, Codable {
    case recording = "recording"
    case processing = "processing"
    case completed = "completed"
}

// MARK: - Meeting Segment

struct MeetingSegment: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval // seconds from start
    let text: String
    var speakerId: String?
    var speakerName: String?
    var isFinal: Bool = true
    
    init(timestamp: TimeInterval, text: String, speakerId: String? = nil, speakerName: String? = nil, isFinal: Bool = true) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.isFinal = isFinal
    }
}

// MARK: - Meeting

struct Meeting: Codable, Identifiable {
    let id: UUID
    var title: String
    let date: Date
    var duration: TimeInterval
    var status: MeetingStatus
    var segments: [MeetingSegment]
    var participantIds: [String] // SpeakerProfile IDs
    
    // LLM Post-processed content
    var summary: String?
    var actionItems: [String] = []
    
    var finalTranscript: String {
        segments.map { segment in
            let name = segment.speakerName ?? "Participant"
            let ts = formatTimestamp(segment.timestamp)
            return "[\(ts)] \(name): \(segment.text)"
        }.joined(separator: "\n")
    }
    
    init(title: String = "Meeting", date: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.duration = 0
        self.status = .recording
        self.segments = []
        self.participantIds = []
    }
    
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
