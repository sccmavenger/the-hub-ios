import Foundation

struct Message: Codable, Identifiable {
    let id: String
    let athleteId: String
    let coachUserId: String
    let senderUserId: String
    let body: String
    var readAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case coachUserId = "coach_user_id"
        case senderUserId = "sender_user_id"
        case body
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    var isRead: Bool { readAt != nil }
}

struct MessageThread: Identifiable {
    let id: String
    let otherPartyId: String
    let otherPartyName: String
    let athleteId: String
    let lastMessage: Message
    var unreadCount: Int
}
