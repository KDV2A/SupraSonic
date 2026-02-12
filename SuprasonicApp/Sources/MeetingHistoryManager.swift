import Foundation

class MeetingHistoryManager {
    static let shared = MeetingHistoryManager()
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var meetingsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport.appendingPathComponent("SupraSonic/meetings")
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    private init() {}
    
    func saveMeeting(_ meeting: Meeting) {
        let fileURL = meetingsDirectory.appendingPathComponent("\(meeting.id.uuidString).json")
        do {
            let data = try encoder.encode(meeting)
            try data.write(to: fileURL)
            print("✅ MeetingHistory: Saved meeting \(meeting.id)")
        } catch {
            print("❌ MeetingHistory: Failed to save meeting: \(error)")
        }
    }
    
    func loadAllMeetings() -> [Meeting] {
        guard let contents = try? fileManager.contentsOfDirectory(at: meetingsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let meetings = contents.compactMap { url -> Meeting? in
            guard url.pathExtension == "json" else { return nil }
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(Meeting.self, from: data)
            } catch {
                print("⚠️ MeetingHistory: Failed to load meeting from \(url.lastPathComponent): \(error)")
                return nil
            }
        }
        
        return meetings.sorted { $0.date > $1.date }
    }
    
    func deleteMeeting(id: UUID) {
        let fileURL = meetingsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
    }
}
