import Foundation
import Supabase

/// Admin side of coach verification. Reads use admin RLS; every decision goes
/// through a 014 RPC so approval stays atomic (program + membership + role +
/// request + notification) and auditable. RLS rejects all of this for
/// non-admins.
final class CoachAdminService {
    static let shared = CoachAdminService()

    private init() {}

    // MARK: - Reads

    func fetchRequests() async throws -> [CoachRequest] {
        try await supabase
            .from("coach_requests")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchRequest(id: String) async throws -> CoachRequest {
        try await supabase
            .from("coach_requests")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func fetchReviews(requestId: String) async throws -> [CoachRequestReview] {
        try await supabase
            .from("coach_request_reviews")
            .select()
            .eq("request_id", value: requestId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Memberships (with program) for one coach — shown on an approved request.
    func fetchMemberships(coachUserId: String) async throws -> [CoachProgramMembership] {
        try await supabase
            .from("coach_program_memberships")
            .select("*, recruiting_programs(*)")
            .eq("coach_user_id", value: coachUserId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Active programs whose normalized name contains `query`.
    func searchPrograms(query: String, limit: Int = 25) async throws -> [RecruitingProgram] {
        let needle = query.trimmed.lowercased()
        var builder = supabase
            .from("recruiting_programs")
            .select()
            .eq("active", value: true)
        if !needle.isEmpty {
            builder = builder.ilike("normalized_institution_name", pattern: "%\(needle)%")
        }
        return try await builder
            .order("institution_name", ascending: true)
            .limit(limit)
            .execute()
            .value
    }

    // MARK: - Decisions (RPCs)

    /// Attributes the admin confirmed for a program that doesn't exist yet.
    struct NewProgram: Equatable {
        var institutionName: String
        var governingBody: GoverningBody
        var division: String?
        var sportGender: SportGender
        var athleticsUrl: String?
        var programUrl: String?

        var json: AnyJSON {
            var object: [String: AnyJSON] = [
                "institution_name": .string(institutionName.trimmed),
                "governing_body": .string(governingBody.rawValue),
                "sport": .string("basketball"),
                "sport_gender": .string(sportGender.rawValue)
            ]
            if let division, !division.isBlank { object["division"] = .string(division.trimmed) }
            if let athleticsUrl, !athleticsUrl.isBlank { object["athletics_url"] = .string(athleticsUrl.trimmed) }
            if let programUrl, !programUrl.isBlank { object["program_url"] = .string(programUrl.trimmed) }
            return .object(object)
        }
    }

    nonisolated struct ApprovalResult: Decodable, Sendable {
        let requestId: String
        let userId: String
        let programId: String
        let membershipId: String
        let status: String

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case userId = "user_id"
            case programId = "program_id"
            case membershipId = "membership_id"
            case status
        }
    }

    private struct ApproveParams: Encodable {
        let p_request_id: String
        let p_program_id: String?
        let p_program: AnyJSON?
        let p_membership_role: String?
        let p_title: String?
        let p_note: String?
    }

    /// Approve against an existing program (verifying it if needed) or a new
    /// admin-confirmed one. One transaction server-side.
    func approve(
        requestId: String,
        existingProgramId: String?,
        newProgram: NewProgram?,
        membershipRole: CoachMembershipRole?,
        verifiedTitle: String?,
        internalNote: String?
    ) async throws -> ApprovalResult {
        try await supabase
            .rpc("approve_coach_request", params: ApproveParams(
                p_request_id: requestId,
                p_program_id: existingProgramId,
                p_program: newProgram?.json,
                p_membership_role: membershipRole?.rawValue,
                p_title: verifiedTitle?.isBlank == false ? verifiedTitle?.trimmed : nil,
                p_note: internalNote?.isBlank == false ? internalNote?.trimmed : nil
            ))
            .execute()
            .value
    }

    private struct ReviewParams: Encodable {
        let p_request_id: String
        let p_reason: String?
        let p_message: String?
        let p_note: String?
    }

    func reject(requestId: String, reason: String, internalNote: String?) async throws -> CoachRequest {
        try await supabase
            .rpc("reject_coach_request", params: ReviewParams(
                p_request_id: requestId, p_reason: reason.trimmed, p_message: nil,
                p_note: internalNote?.isBlank == false ? internalNote?.trimmed : nil
            ))
            .execute()
            .value
    }

    func requestInfo(requestId: String, message: String, internalNote: String?) async throws -> CoachRequest {
        try await supabase
            .rpc("request_coach_info", params: ReviewParams(
                p_request_id: requestId, p_reason: nil, p_message: message.trimmed,
                p_note: internalNote?.isBlank == false ? internalNote?.trimmed : nil
            ))
            .execute()
            .value
    }

    private struct MembershipStatusParams: Encodable {
        let p_membership_id: String
        let p_status: String
        let p_note: String?
    }

    nonisolated struct MembershipStatusResult: Decodable, Sendable {
        let membershipId: String
        let status: CoachMembershipStatus
        let hasCoachRole: Bool

        enum CodingKeys: String, CodingKey {
            case membershipId = "membership_id"
            case status
            case hasCoachRole = "has_coach_role"
        }
    }

    /// Suspend / inactivate / reinstate. The coach role follows server-side.
    func setMembershipStatus(
        membershipId: String,
        status: CoachMembershipStatus,
        internalNote: String?
    ) async throws -> MembershipStatusResult {
        try await supabase
            .rpc("set_coach_membership_status", params: MembershipStatusParams(
                p_membership_id: membershipId,
                p_status: status.rawValue,
                p_note: internalNote?.isBlank == false ? internalNote?.trimmed : nil
            ))
            .execute()
            .value
    }
}
