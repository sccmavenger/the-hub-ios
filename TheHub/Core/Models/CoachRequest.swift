import Foundation

/// A coach's application for College Coach access (`coach_requests`). Every
/// program field here is a *claim* awaiting admin review; the verified truth
/// lives in `recruiting_programs` / `coach_program_memberships` once approved.
// nonisolated: the target defaults types to @MainActor; decoding happens off
// the main actor inside the Supabase client, so the conformances must not be
// actor-isolated.
nonisolated struct CoachRequest: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    var fullName: String
    let email: String
    var title: String?
    /// Claimed institution. Column is `college` for compatibility with the
    /// original schema.
    var college: String?
    /// Applicant's free-text verification note.
    var message: String?
    var status: CoachRequestStatus
    var reviewedAt: String?
    var reviewedBy: String?
    let createdAt: String

    // Program claims (014)
    var governingBody: String?
    var division: String?
    var sport: String?
    var sportGender: String?
    var athleticsUrl: String?
    var programUrl: String?
    var phone: String?

    // Review outcome, user-visible (internal notes are admin-only elsewhere)
    var rejectionReason: String?
    var infoRequestMessage: String?
    var resubmittedAt: String?
    var approvedProgramId: String?
    var approvedMembershipId: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fullName = "full_name"
        case email
        case title
        case college
        case message
        case status
        case reviewedAt = "reviewed_at"
        case reviewedBy = "reviewed_by"
        case createdAt = "created_at"
        case governingBody = "governing_body"
        case division
        case sport
        case sportGender = "sport_gender"
        case athleticsUrl = "athletics_url"
        case programUrl = "program_url"
        case phone
        case rejectionReason = "rejection_reason"
        case infoRequestMessage = "info_request_message"
        case resubmittedAt = "resubmitted_at"
        case approvedProgramId = "approved_program_id"
        case approvedMembershipId = "approved_membership_id"
        case updatedAt = "updated_at"
    }

    /// "Men's Basketball" / "Women's Basketball" / "Basketball".
    var programLabel: String {
        let gender = SportGender(rawValue: sportGender ?? "")?.displayName
        let sportName = (sport ?? "basketball").capitalized
        return [gender, sportName].compactMap { $0 }.joined(separator: " ")
    }

    /// "NCAA Division I" or nil when the claim is missing/unknown.
    var divisionLabel: String? {
        GoverningBody.divisionLabel(governingBody: governingBody, division: division)
    }

    /// Whether the applicant may edit and resubmit (mirrors update_coach_application).
    var isEditable: Bool {
        switch status {
        case .pending, .rejected, .needsMoreInformation, .withdrawn: true
        case .approved: false
        }
    }
}
