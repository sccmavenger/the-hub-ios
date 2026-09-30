import Foundation

/// Coach bookmark as visible to the athlete — identity and date only,
/// via the bookmarks_for_athlete RPC (stage/tags/notes stay coach-private).
struct BookmarkSummary: Codable, Identifiable {
    let coachUserId: String
    let coachName: String
    let college: String?
    let title: String?
    let savedAt: String

    enum CodingKeys: String, CodingKey {
        case coachUserId = "coach_user_id"
        case coachName = "coach_name"
        case college
        case title
        case savedAt = "saved_at"
    }

    var id: String { coachUserId }
}

/// Approved coach's public label, via the coach_directory_names RPC.
struct CoachDirectoryEntry: Codable, Identifiable {
    let userId: String
    let coachName: String
    let college: String?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case coachName = "coach_name"
        case college
        case title
    }

    var id: String { userId }
}
