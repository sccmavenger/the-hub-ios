import Foundation

struct UserRole: Codable, Identifiable {
    let id: String
    let userId: String
    let role: AppRole
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case role
        case createdAt = "created_at"
    }
}
