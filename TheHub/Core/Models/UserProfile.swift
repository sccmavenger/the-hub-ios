import Foundation

struct UserProfile: Codable, Identifiable {
    let id: String
    let email: String?
    let displayName: String?
    let avatarUrl: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
