import Foundation

struct AppNotification: Codable, Identifiable {
    let id: String
    let userId: String
    let title: String
    var body: String?
    let type: String
    var link: String?
    var readAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case body
        case type
        case link
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    var isRead: Bool { readAt != nil }
}
