import Foundation

/// Where a notification takes the user when tapped (spec D28, migration 020).
/// The server writes `notifications.destination` as `{"type": ..., ...}`;
/// legacy web `link` strings are mapped to the same shape by a database
/// trigger, so the client never parses URLs. Unknown types decode as
/// `.unknown` and simply mark the row read.
nonisolated enum NotificationDestination: Equatable, Sendable {
    case athlete(athleteId: String)
    case messages
    case thread(athleteId: String, coachUserId: String)
    case savedSearch(id: String, programId: String?)
    case discover
    case coachHome
    case coachApplication
    case adminCoaches
    case adminReports
    case unknown(type: String)

    /// True when tapping leads somewhere (drives the chevron in the list).
    var isNavigable: Bool {
        if case .unknown = self { return false }
        return true
    }
}

extension NotificationDestination: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case athleteId = "athlete_id"
        case coachUserId = "coach_user_id"
        case savedSearchId = "saved_search_id"
        case programId = "program_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "athlete":
            if let id = try c.decodeIfPresent(String.self, forKey: .athleteId) {
                self = .athlete(athleteId: id)
            } else {
                self = .unknown(type: type)
            }
        case "messages":
            self = .messages
        case "thread":
            if let athleteId = try c.decodeIfPresent(String.self, forKey: .athleteId),
               let coachUserId = try c.decodeIfPresent(String.self, forKey: .coachUserId) {
                self = .thread(athleteId: athleteId, coachUserId: coachUserId)
            } else {
                self = .unknown(type: type)
            }
        case "saved_search":
            if let id = try c.decodeIfPresent(String.self, forKey: .savedSearchId) {
                self = .savedSearch(id: id, programId: try c.decodeIfPresent(String.self, forKey: .programId))
            } else {
                self = .unknown(type: type)
            }
        case "discover": self = .discover
        case "coach_home": self = .coachHome
        case "coach_application": self = .coachApplication
        case "admin_coaches": self = .adminCoaches
        case "admin_reports": self = .adminReports
        default: self = .unknown(type: type)
        }
    }
}

nonisolated struct AppNotification: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    let title: String
    var body: String?
    let type: String
    var link: String?
    var destination: NotificationDestination?
    var readAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case body
        case type
        case link
        case destination
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        type = try c.decode(String.self, forKey: .type)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        // A malformed destination must not hide the notification itself.
        destination = try? c.decodeIfPresent(NotificationDestination.self, forKey: .destination)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(link, forKey: .link)
        try c.encodeIfPresent(readAt, forKey: .readAt)
        try c.encode(createdAt, forKey: .createdAt)
    }

    var isRead: Bool { readAt != nil }

    /// SF Symbol for the row, by server-side `type`.
    var symbolName: String {
        switch type {
        case "message": "message.fill"
        case "bookmark": "bookmark.fill"
        case "interest": "star.fill"
        case "saved_search": "sparkle.magnifyingglass"
        case "report": "exclamationmark.bubble.fill"
        case let t where t.hasPrefix("coach_"): "checkmark.seal.fill"
        default: "bell.fill"
        }
    }
}
