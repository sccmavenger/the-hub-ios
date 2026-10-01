import Foundation
import Supabase

// Coach-facing models (supabase/016, 017). Every athlete payload a coach
// receives is the server's safe-field allowlist (`coach_athlete_card_json`);
// nothing here can widen it.

/// One athlete as a coach may see them (spec §6.2). No DOB, test scores,
/// NCAA id, zip, coordinates, consent fields or user id exist in this type.
nonisolated struct CoachAthleteCard: Codable, Identifiable, Equatable, Sendable {
    let athleteId: String
    let fullName: String
    var profilePhotoPath: String?
    var highSchool: String?
    var hometown: String?
    var state: String?
    var gradYear: Int?
    var position: String?
    var jerseyNumber: String?
    var heightInches: Int?
    var weightLbs: Int?
    var gpa: Double?
    var bio: String?
    var intendedMajor: String?
    var instagramHandle: String?
    var tiktokHandle: String?
    var sportGender: String?
    var isPublished: Bool
    /// Rounded to the nearest 5 miles by the server; nil without a search center.
    var distanceMiles: Int?
    /// Discover only (018): the program's active board stage for this athlete.
    var boardStage: String?
    /// Discover only (018): next event on/after today, ISO date.
    var nextEventDate: String?

    var id: String { athleteId }

    var boardPipelineStage: PipelineStage? {
        boardStage.flatMap(PipelineStage.init(rawValue:))
    }

    enum CodingKeys: String, CodingKey {
        case athleteId = "athlete_id"
        case fullName = "full_name"
        case profilePhotoPath = "profile_photo_path"
        case highSchool = "high_school"
        case hometown, state
        case gradYear = "grad_year"
        case position
        case jerseyNumber = "jersey_number"
        case heightInches = "height_inches"
        case weightLbs = "weight_lbs"
        case gpa, bio
        case intendedMajor = "intended_major"
        case instagramHandle = "instagram_handle"
        case tiktokHandle = "tiktok_handle"
        case sportGender = "sport_gender"
        case isPublished = "is_published"
        case distanceMiles = "distance_miles"
        case boardStage = "board_stage"
        case nextEventDate = "next_event_date"
    }

    var heightDisplay: String? {
        guard let inches = heightInches else { return nil }
        return "\(inches / 12)'\(inches % 12)\""
    }

    var classLabel: String? {
        gradYear.map { "Class of \($0)" }
    }

    /// "CW High · St. Louis, MO"
    var schoolLine: String? {
        let place = [hometown, state].compactMap { $0 }.joined(separator: ", ")
        return [highSchool, place.isEmpty ? nil : place].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }
}

nonisolated struct CoachPhoto: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var storagePath: String?
    var caption: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case storagePath = "storage_path"
        case caption
        case createdAt = "created_at"
    }
}

nonisolated struct CoachVideo: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let url: String
    var title: String?
}

nonisolated struct CoachEvent: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let eventDate: String
    var eventTime: String?
    var opponent: String?
    var location: String?
    var notes: String?
    var isMayb: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case eventDate = "event_date"
        case eventTime = "event_time"
        case opponent, location, notes
        case isMayb = "is_mayb"
    }
}

/// Contact card fields, present only after the program saved the athlete (D25).
nonisolated struct CoachContact: Codable, Equatable, Sendable {
    var athleteEmail: String?
    var athletePhone: String?
    var guardianName: String?
    var guardianEmail: String?
    var guardianPhone: String?
    var clubCoachName: String?
    var clubCoachPhone: String?

    enum CodingKeys: String, CodingKey {
        case athleteEmail = "athlete_email"
        case athletePhone = "athlete_phone"
        case guardianName = "guardian_name"
        case guardianEmail = "guardian_email"
        case guardianPhone = "guardian_phone"
        case clubCoachName = "club_coach_name"
        case clubCoachPhone = "club_coach_phone"
    }

    var isEmpty: Bool {
        [athleteEmail, athletePhone, guardianName, guardianEmail, guardianPhone, clubCoachName, clubCoachPhone]
            .allSatisfy { ($0 ?? "").isEmpty }
    }
}

/// A row on the program's shared Recruiting Board (017).
nonisolated struct BoardEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let programId: String
    let athleteId: String
    var stage: PipelineStage
    var tags: [String]
    var assignedTo: String?
    var assignedToName: String?
    var savedBy: String?
    var savedByName: String?
    var removedAt: String?
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case programId = "program_id"
        case athleteId = "athlete_id"
        case stage, tags
        case assignedTo = "assigned_to"
        case assignedToName = "assigned_to_name"
        case savedBy = "saved_by"
        case savedByName = "saved_by_name"
        case removedAt = "removed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isRemoved: Bool { removedAt != nil }

    static let maxTags = 10
    static let maxTagLength = 30
    static let maxNoteLength = 2000
}

/// Full detail payload from `coach_athlete_detail`.
nonisolated struct CoachAthleteDetail: Codable, Equatable, Sendable {
    let athlete: CoachAthleteCard
    var photos: [CoachPhoto]
    var videos: [CoachVideo]
    var upcomingEvents: [CoachEvent]
    var contactUnlocked: Bool
    var contact: CoachContact?
    var board: BoardEntry?
    var privateNote: String?
    let programId: String

    enum CodingKeys: String, CodingKey {
        case athlete, photos, videos
        case upcomingEvents = "upcoming_events"
        case contactUnlocked = "contact_unlocked"
        case contact, board
        case privateNote = "private_note"
        case programId = "program_id"
    }
}

nonisolated struct BoardListItem: Codable, Identifiable, Equatable, Sendable {
    let entry: BoardEntry
    let athlete: CoachAthleteCard
    var hasPrivateNote: Bool

    var id: String { entry.id }

    enum CodingKeys: String, CodingKey {
        case entry, athlete
        case hasPrivateNote = "has_private_note"
    }
}

nonisolated struct BoardListPage: Codable, Equatable, Sendable {
    var items: [BoardListItem]
    var nextCursor: AnyJSON?
    var stageCounts: [String: Int]
    var assignedToMe: Int

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case stageCounts = "stage_counts"
        case assignedToMe = "assigned_to_me"
    }

    func count(for stage: PipelineStage) -> Int { stageCounts[stage.rawValue] ?? 0 }
    var total: Int { stageCounts.values.reduce(0, +) }
}

nonisolated struct BoardActivity: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let entryId: String
    let athleteId: String
    let athleteName: String
    var actorUserId: String?
    var actorName: String?
    let action: String
    var fromValue: String?
    var toValue: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case athleteId = "athlete_id"
        case athleteName = "athlete_name"
        case actorUserId = "actor_user_id"
        case actorName = "actor_name"
        case action
        case fromValue = "from_value"
        case toValue = "to_value"
        case createdAt = "created_at"
    }

    /// "Coach One moved Jordan to Evaluating"
    var summary: String {
        let actor = actorName ?? "A coach"
        switch action {
        case "saved": return "\(actor) saved \(athleteName)"
        case "restored": return "\(actor) restored \(athleteName) to the board"
        case "removed": return "\(actor) removed \(athleteName)"
        case "stage_changed":
            let to = toValue.flatMap { PipelineStage(rawValue: $0)?.displayName } ?? (toValue ?? "")
            return "\(actor) moved \(athleteName) to \(to)"
        case "tags_changed": return "\(actor) updated tags for \(athleteName)"
        case "assigned": return "\(actor) assigned \(athleteName) to \(toValue ?? "a coach")"
        case "unassigned": return "\(actor) unassigned \(athleteName)"
        default: return "\(actor) updated \(athleteName)"
        }
    }
}

nonisolated struct CoachPrivateNote: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let coachUserId: String
    let athleteId: String
    var body: String
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case coachUserId = "coach_user_id"
        case athleteId = "athlete_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct ProgramStaffMember: Codable, Identifiable, Equatable, Sendable {
    let userId: String
    let displayName: String
    var title: String?
    var membershipRole: String?
    var verifiedAt: String?
    var isMe: Bool

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case title
        case membershipRole = "membership_role"
        case verifiedAt = "verified_at"
        case isMe = "is_me"
    }

    var roleDisplayName: String? {
        membershipRole.flatMap { CoachMembershipRole(rawValue: $0)?.displayName }
    }
}

nonisolated struct CoachHomeSummary: Codable, Equatable, Sendable {
    var unreadThreads: Int
    var savedSearches: Int
    var boardCounts: [String: Int]
    var assignedToMe: Int
    var recentActivity: [BoardActivity]

    enum CodingKeys: String, CodingKey {
        case unreadThreads = "unread_threads"
        case savedSearches = "saved_searches"
        case boardCounts = "board_counts"
        case assignedToMe = "assigned_to_me"
        case recentActivity = "recent_activity"
    }

    func count(for stage: PipelineStage) -> Int { boardCounts[stage.rawValue] ?? 0 }
    var boardTotal: Int { boardCounts.values.reduce(0, +) }
}

/// One conversation in the coach inbox (`coach_inbox`, 019).
nonisolated struct CoachInboxThread: Codable, Identifiable, Equatable, Sendable {
    nonisolated struct LastMessage: Codable, Equatable, Sendable {
        let id: String
        let body: String
        let senderUserId: String
        let createdAt: String
        var complianceStatus: String?

        enum CodingKeys: String, CodingKey {
            case id, body
            case senderUserId = "sender_user_id"
            case createdAt = "created_at"
            case complianceStatus = "compliance_status"
        }
    }

    let athlete: CoachAthleteCard
    var lastMessage: LastMessage?
    var unreadCount: Int
    var boardStage: String?

    var id: String { athlete.athleteId }

    enum CodingKeys: String, CodingKey {
        case athlete
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case boardStage = "board_stage"
    }

    var boardPipelineStage: PipelineStage? { boardStage.flatMap(PipelineStage.init(rawValue:)) }
}

/// Result of `send_coach_message` (019). `denied` carries the decision that
/// refused the send; the attempt is already recorded server-side.
nonisolated struct CoachSendResult: Codable, Equatable, Sendable {
    nonisolated enum Status: String, Codable, Sendable {
        case sent
        case denied
    }

    let status: Status
    let decision: RecruitingDecision?
    let message: Message?
}

extension RecruitingDecision {
    /// Coach-side explanation for a `needs_review`. The stock hint is worded
    /// for the athlete; coaches need to know whether the gap is theirs, the
    /// program's, or the athlete's profile — and that the send is still allowed.
    var coachMissingContextHint: String? {
        guard status == .needsReview else { return nil }
        if missingContext.contains("coach.verified_program") {
            return "Your program membership isn't verified for this athlete's sport yet, so no rule can be applied. The message is allowed but not evaluated."
        }
        if missingContext.contains("coach.verified_program.ambiguous") {
            return "You're verified with more than one program for this sport. Choose the program you're recruiting for from the Program tab."
        }
        if missingContext.contains("program.sport_gender.mismatch") {
            return "This program recruits a different gender than this athlete's profile lists."
        }
        if missingContext.contains("athlete.grad_year") || missingContext.contains("athlete.sport_gender") {
            return "This athlete's profile is missing the class year or program that the rule keys on. The message is allowed but not evaluated."
        }
        if missingContext.contains("rule") {
            return "No published rule covers this program's association and division yet. The message is allowed but not evaluated."
        }
        return "The Hub couldn't match a rule to this send. It is allowed but not evaluated."
    }

    /// True when the database will refuse this send with enforcement on.
    var wouldHardBlock: Bool {
        status == .prohibited && enforcement == .hardBlock && isVerifiedContext
    }
}

/// A page of Discover results from `search_published_athletes`.
nonisolated struct AthleteSearchPage: Codable, Equatable, Sendable {
    var items: [CoachAthleteCard]
    var nextCursor: AnyJSON?
    var total: Int
    let programId: String
    let sportGender: String

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case total
        case programId = "program_id"
        case sportGender = "sport_gender"
    }

    var hasMore: Bool {
        if let nextCursor, nextCursor != .null { return true }
        return false
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Client mirror of `coach_tags_clean()` (017) so the editor can refuse bad
/// input before the round-trip. The database check remains authoritative.
nonisolated enum BoardTags {
    enum ValidationError: Error, Equatable {
        case tooLong(String)
        case tooMany
    }

    static func clean(_ tags: [String]) throws -> [String] {
        var cleaned: [String] = []
        for raw in tags {
            let tag = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if tag.isEmpty { continue }
            if tag.count > BoardEntry.maxTagLength { throw ValidationError.tooLong(tag) }
            if !cleaned.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                cleaned.append(tag)
            }
        }
        if cleaned.count > BoardEntry.maxTags { throw ValidationError.tooMany }
        return cleaned
    }
}
