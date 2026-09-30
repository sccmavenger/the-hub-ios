import Foundation
import Supabase

/// Recruiting action taxonomy shared with the backend (spec §5). Raw values
/// are the `action_type` strings stored in `recruiting_rules`. Actions are
/// modeled separately on purpose: an opening for one (e.g. electronic
/// messages) never implies an opening for another (calls, visits, contact).
nonisolated enum RecruitingAction: String, Codable, CaseIterable, Sendable {
    case athleteSendIntroMessage = "athlete_send_intro_message"
    case coachSendRecruitingElectronicCorrespondence = "coach_send_recruiting_electronic_correspondence"
    case coachSendNonrecruitingResponse = "coach_send_nonrecruiting_response"
    case coachPlacePhoneOrVideoCall = "coach_place_phone_or_video_call"
    case coachOffCampusContact = "coach_off_campus_contact"
    case coachInPersonEvaluation = "coach_in_person_evaluation"
    case athleteOfficialVisit = "athlete_official_visit"
    case athleteUnofficialVisit = "athlete_unofficial_visit"
    case institutionSendRecruitingMaterial = "institution_send_recruiting_material"
    case institutionSendCampLogistics = "institution_send_camp_logistics"
}

nonisolated enum RecruitingDecisionStatus: String, Codable, Sendable {
    case permitted
    case prohibited
    case permittedWithRestrictions = "permitted_with_restrictions"
    case needsReview = "needs_review"
}

nonisolated enum EnforcementLevel: String, Codable, Sendable {
    case hardBlock = "hard_block"
    case warning
    case informational
    case none
}

/// The backend's answer to "is this action permitted for this actor, athlete,
/// program and date?" — deserialized verbatim from `evaluate_recruiting_action`
/// (supabase/011). The client never derives a rule outcome itself; it only
/// renders this. Timestamps stay as the server's strings and are parsed on
/// read so an unexpected format degrades to "no date" rather than a decode
/// failure.
nonisolated struct RecruitingDecision: Codable, Equatable, Sendable {
    let status: RecruitingDecisionStatus
    let action: String
    let actor: String?
    let reason: String
    let userMessage: String
    let nextPermittedAt: String?
    /// Calendar date of `nextPermittedAt` in the rule's own time zone.
    let nextPermittedOn: String?
    let ruleTimeZone: String?
    let enforcement: EnforcementLevel
    let missingContext: [String]
    let conflict: Bool
    let governingBody: String?
    let division: String?
    let sport: String?
    let sportGender: String?
    /// `verified_program`, `unverified_program`, `client_supplied`, or `none`.
    /// Only `verified_program` decisions can ever hard-block (server-side).
    let contextSource: String
    let evaluatedAt: String?
    let ruleId: String?
    let ruleKey: String?
    let ruleVersion: Int?
    let sourceTitle: String?
    let sourceUrl: String?
    let sourceReference: String?
    let effectiveFrom: String?
    let effectiveUntil: String?
    let lastVerifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case action
        case actor
        case reason
        case userMessage = "user_message"
        case nextPermittedAt = "next_permitted_at"
        case nextPermittedOn = "next_permitted_on"
        case ruleTimeZone = "rule_time_zone"
        case enforcement
        case missingContext = "missing_context"
        case conflict
        case governingBody = "governing_body"
        case division
        case sport
        case sportGender = "sport_gender"
        case contextSource = "context_source"
        case evaluatedAt = "evaluated_at"
        case ruleId = "rule_id"
        case ruleKey = "rule_key"
        case ruleVersion = "rule_version"
        case sourceTitle = "source_title"
        case sourceUrl = "source_url"
        case sourceReference = "source_reference"
        case effectiveFrom = "effective_from"
        case effectiveUntil = "effective_until"
        case lastVerifiedAt = "last_verified_at"
    }

    // MARK: Derived (presentation only — no rule logic)

    var nextPermittedDate: Date? { nextPermittedAt?.asDate() }
    var lastVerifiedDate: Date? { lastVerifiedAt?.asDate() }
    var effectiveFromDate: Date? { effectiveFrom?.asDate() }
    var evaluatedDate: Date? { evaluatedAt?.asDate() }
    var sourceLink: URL? { sourceUrl.flatMap(URL.init(string:)) }
    var isVerifiedContext: Bool { contextSource == "verified_program" }

    /// Short badge text (spec §31: plain words, never "illegal"/"violation").
    var badgeLabel: String {
        switch status {
        case .permitted: "Allowed"
        case .prohibited: nextPermittedOn == nil && nextPermittedAt == nil ? "Not allowed" : "Not yet"
        case .permittedWithRestrictions: "Allowed, with limits"
        case .needsReview: "Needs review"
        }
    }

    /// "June 15, 2027" in the rule's calendar, when the decision has a date.
    var nextPermittedDisplay: String? {
        if let on = nextPermittedOn { return on.asFormattedDate(style: .long) }
        return nextPermittedDate?.formatted(date: .long, time: .omitted)
    }

    /// What the athlete can do about a `needs_review` caused by their own
    /// missing profile facts. Nil when the gap is on the rules/program side —
    /// `userMessage` already explains that The Hub won't guess.
    var missingContextHint: String? {
        if missingContext.contains("athlete.sport_gender") {
            return "Set boys/girls basketball in your profile to see the rule that applies to you."
        }
        if missingContext.contains("athlete.grad_year") {
            return "Add your graduation year on the Profile tab to see when this opens."
        }
        if missingContext.contains("athlete.sophomore_completed_on") {
            return "Your profile uses a nontraditional school calendar. Email info@summithoops.net with the date your sophomore year ended and we'll apply the matching rule."
        }
        return nil
    }
}

/// UI load state for one decision. `.unavailable` covers network failure,
/// decode failure, and the engine flag being off — never a guessed outcome.
nonisolated enum RecruitingStatusLoad: Equatable, Sendable {
    case loading
    case loaded(RecruitingDecision)
    case unavailable
}

enum RecruitingRulesError: Error, Equatable {
    /// `recruiting_rules_engine_enabled` is off (or unreadable → fail closed).
    case engineDisabled
    /// The database rejected an in-app action under a verified rule (013).
    case actionProhibited(userMessage: String, decision: RecruitingDecision?)

    static let defaultProhibitedMessage =
        "This recruiting message can't be sent yet under the rule currently applicable to this program and athlete."

    /// Maps the stable `RECRUITING_ACTION_PROHIBITED` rejection raised by the
    /// messages trigger. Anything else returns nil so callers keep their
    /// existing error handling.
    static func fromServerError(_ error: any Error) -> RecruitingRulesError? {
        guard let pg = error as? PostgrestError, pg.message == "RECRUITING_ACTION_PROHIBITED" else {
            return nil
        }
        let decision = pg.details
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(RecruitingDecision.self, from: $0) }
        let message = decision?.userMessage ?? pg.hint ?? defaultProhibitedMessage
        return .actionProhibited(userMessage: message, decision: decision)
    }

    var userMessage: String {
        switch self {
        case .engineDisabled: "Recruiting status unavailable."
        case .actionProhibited(let message, _): message
        }
    }
}
