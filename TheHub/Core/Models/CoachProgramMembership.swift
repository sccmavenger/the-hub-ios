import Foundation

/// Mirrors `coach_program_memberships.status` (014).
nonisolated enum CoachMembershipStatus: String, Codable, Sendable {
    case pending
    case verified
    case suspended
    case inactive
    case rejected

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .verified: "Verified"
        case .suspended: "Suspended"
        case .inactive: "Inactive"
        case .rejected: "Rejected"
        }
    }
}

/// Mirrors `coach_program_memberships.membership_role` (014). Not only
/// head/assistant coaches use the system.
nonisolated enum CoachMembershipRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case headCoach = "head_coach"
    case assistantCoach = "assistant_coach"
    case recruitingCoordinator = "recruiting_coordinator"
    case operations
    case staff
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .headCoach: "Head Coach"
        case .assistantCoach: "Assistant Coach"
        case .recruitingCoordinator: "Recruiting Coordinator"
        case .operations: "Operations"
        case .staff: "Staff"
        case .other: "Other"
        }
    }
}

/// A coach's association with one program (`coach_program_memberships`).
/// The `coach` role exists exactly while ≥1 membership is `verified` in an
/// active, verified program — see sync_coach_role() in supabase/014.
nonisolated struct CoachProgramMembership: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let coachUserId: String
    let programId: String
    var title: String?
    var membershipRole: String?
    var status: CoachMembershipStatus
    var verifiedAt: String?
    var verifiedBy: String?
    var startedAt: String?
    var endedAt: String?
    let createdAt: String
    var updatedAt: String?
    /// Present when fetched with `recruiting_programs(*)` embedded.
    var program: RecruitingProgram?

    enum CodingKeys: String, CodingKey {
        case id
        case coachUserId = "coach_user_id"
        case programId = "program_id"
        case title
        case membershipRole = "membership_role"
        case status
        case verifiedAt = "verified_at"
        case verifiedBy = "verified_by"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case program = "recruiting_programs"
    }

    var roleDisplayName: String? {
        membershipRole.flatMap { CoachMembershipRole(rawValue: $0)?.displayName }
    }
}

/// One entry in the admin-only review log (`coach_request_reviews`).
nonisolated struct CoachRequestReview: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let requestId: String
    let action: String
    var actorUserId: String?
    var publicMessage: String?
    var internalNote: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case action
        case actorUserId = "actor_user_id"
        case publicMessage = "public_message"
        case internalNote = "internal_note"
        case createdAt = "created_at"
    }

    var actionDisplayName: String {
        switch action {
        case "submitted": "Submitted"
        case "resubmitted": "Resubmitted"
        case "approved": "Approved"
        case "rejected": "Rejected"
        case "info_requested": "More information requested"
        case "withdrawn": "Withdrawn"
        case "membership_suspended": "Membership suspended"
        case "membership_inactivated": "Membership inactivated"
        case "membership_reinstated": "Membership reinstated"
        default: action.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
