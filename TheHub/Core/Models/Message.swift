import Foundation

nonisolated struct Message: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let athleteId: String
    let coachUserId: String
    let senderUserId: String
    let body: String
    var readAt: String?
    let createdAt: String
    /// The coach's representing program for a coach send (019); nil for athlete sends.
    var programId: String?
    /// Rules-engine stamp set by the database trigger (013/019); nil for athlete sends.
    var complianceStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case coachUserId = "coach_user_id"
        case senderUserId = "sender_user_id"
        case body
        case readAt = "read_at"
        case createdAt = "created_at"
        case programId = "program_id"
        case complianceStatus = "compliance_status"
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
