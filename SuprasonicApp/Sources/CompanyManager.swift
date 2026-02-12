import Foundation

class CompanyManager {
    static let shared = CompanyManager()
    
    private var members: [CompanyMember] = []
    
    private init() {
        setupMockDirectory()
    }
    
    private func setupMockDirectory() {
        members = [
            CompanyMember(id: "1", name: "Marc Dupont", role: "CEO", initials: "MD", colorHex: "#00E5FF"),
            CompanyMember(id: "2", name: "Sophie Martin", role: "Product Manager", initials: "SM", colorHex: "#FF4081"),
            CompanyMember(id: "3", name: "John Smith", role: "Lead Engineer", initials: "JS", colorHex: "#7C4DFF"),
            CompanyMember(id: "4", name: "Hélène Dubois", role: "UX Designer", initials: "HD", colorHex: "#00C853")
        ]
    }
    
    func findMember(for speakerId: String) -> CompanyMember? {
        // In a real app, we'd have a mapping of speaker fingerprints to members.
        // For this demo, we'll use a simple deterministic mapping based on ID.
        let index: Int
        if speakerId.contains("_") {
            let parts = speakerId.components(separatedBy: "_")
            if let last = parts.last, let val = Int(last) {
                index = (val - 1) % members.count
            } else {
                index = 0
            }
        } else {
            index = abs(speakerId.hashValue) % members.count
        }
        
        return members[index]
    }
    
    func getAllMembers() -> [CompanyMember] {
        return members
    }
}
