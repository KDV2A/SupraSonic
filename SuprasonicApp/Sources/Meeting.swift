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
    var text: String
    var speakerId: String?
    var speakerName: String?
    var isFinal: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, text, speakerId, speakerName, isFinal
    }
    
    init(timestamp: TimeInterval, text: String, speakerId: String? = nil, speakerName: String? = nil, isFinal: Bool = true) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.isFinal = isFinal
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? 0
        text = try container.decode(String.self, forKey: .text)
        speakerId = try container.decodeIfPresent(String.self, forKey: .speakerId)
        speakerName = try container.decodeIfPresent(String.self, forKey: .speakerName)
        isFinal = try container.decodeIfPresent(Bool.self, forKey: .isFinal) ?? true
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
    var participantIds: [String]
    
    // LLM Post-processed content
    var summary: String?
    var actionItems: [String] = []
    
    enum CodingKeys: String, CodingKey {
        case id, title, date, duration, status, segments, participantIds, summary, actionItems
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(Date.self, forKey: .date)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        status = try container.decodeIfPresent(MeetingStatus.self, forKey: .status) ?? .completed
        segments = try container.decodeIfPresent([MeetingSegment].self, forKey: .segments) ?? []
        participantIds = try container.decodeIfPresent([String].self, forKey: .participantIds) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems) ?? []
    }
    
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
