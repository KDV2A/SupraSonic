import Foundation

struct CompanyMember: Codable, Identifiable {
    let id: String // Can be email or unique ID
    let name: String
    let role: String
    let initials: String
    let colorHex: String // For avatar background
    
    var initialsImage: String {
        return initials.uppercased()
    }
}
