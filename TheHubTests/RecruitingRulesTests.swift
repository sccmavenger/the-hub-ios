import Foundation
import Testing
import Supabase
@testable import TheHub

/// Client-side tests for the Recruiting Rules Engine (spec §29.3 model/service
/// slice). Rule *logic* is tested in SQL (supabase/tests); these cover that
/// the app faithfully deserializes, presents, caches and maps what the
/// backend returns — and never invents a decision of its own.
@Suite("Recruiting rules — client")
struct RecruitingRulesTests {

    // Fixture shaped exactly like evaluate_recruiting_action's JSON.
    static let prohibitedJSON = """
    {
      "status": "prohibited",
      "action": "coach_send_recruiting_electronic_correspondence",
      "actor": "coach",
      "reason": "Rule ncaa.d1.basketball.mens.coach.electronic_correspondence v1",
      "user_message": "Under NCAA Division I rules for men's basketball, a college program may not send you recruiting materials or electronic messages until June 15 after your sophomore year of high school.",
      "next_permitted_at": "2027-06-15T04:00:00Z",
      "next_permitted_on": "2027-06-15",
      "rule_time_zone": "America/Indiana/Indianapolis",
      "enforcement": "hard_block",
      "missing_context": [],
      "conflict": false,
      "governing_body": "NCAA",
      "division": "D1",
      "sport": "basketball",
      "sport_gender": "mens",
      "context_source": "client_supplied",
      "evaluated_at": "2026-09-30T12:00:00Z",
      "rule_id": "b1b2c3d4-0002-4000-8000-000000000001",
      "rule_key": "ncaa.d1.basketball.mens.coach.electronic_correspondence",
      "rule_version": 1,
      "source_title": "NCAA Division I Manual 2026-27 (LSDBi report 90008)",
      "source_url": "https://web3.ncaa.org/lsdbi/reports/getReport/90008",
      "source_reference": "Bylaw 13.4.1.5 Exception — Men's Basketball",
      "effective_from": "2026-08-01",
      "effective_until": null,
      "last_verified_at": "2026-09-30T00:00:00Z"
    }
    """

    static let needsReviewJSON = """
    {
      "status": "needs_review",
      "action": "coach_send_recruiting_electronic_correspondence",
      "actor": "coach",
      "reason": "Required context is missing: athlete.sport_gender",
      "user_message": "We don't have enough verified information to determine this recruiting action. The Hub won't guess.",
      "next_permitted_at": null,
      "next_permitted_on": null,
      "rule_time_zone": null,
      "enforcement": "none",
      "missing_context": ["athlete.sport_gender"],
      "conflict": false,
      "governing_body": "NCAA",
      "division": "D2",
      "sport": "basketball",
      "sport_gender": null,
      "context_source": "client_supplied",
      "evaluated_at": "2026-09-30T12:00:00Z",
      "rule_id": null,
      "rule_key": null,
      "rule_version": null,
      "source_title": null,
      "source_url": null,
      "source_reference": null,
      "effective_from": null,
      "effective_until": null,
      "last_verified_at": null
    }
    """

    static func decode(_ json: String) throws -> RecruitingDecision {
        try JSONDecoder().decode(RecruitingDecision.self, from: Data(json.utf8))
    }

    static func decision(status: RecruitingDecisionStatus, next: String? = nil, missing: [String] = []) -> RecruitingDecision {
        RecruitingDecision(
            status: status, action: "x", actor: "coach", reason: "r", userMessage: "m",
            nextPermittedAt: next, nextPermittedOn: next.map { String($0.prefix(10)) }, ruleTimeZone: nil,
            enforcement: .none, missingContext: missing, conflict: false,
            governingBody: "NCAA", division: "D1", sport: "basketball", sportGender: "mens",
            contextSource: "client_supplied", evaluatedAt: nil, ruleId: nil, ruleKey: nil, ruleVersion: nil,
            sourceTitle: nil, sourceUrl: nil, sourceReference: nil, effectiveFrom: nil, effectiveUntil: nil,
            lastVerifiedAt: nil
        )
    }

    // MARK: Decoding

    @Test("Prohibited decision decodes with every attribution field")
    func decodesProhibited() throws {
        let d = try Self.decode(Self.prohibitedJSON)
        #expect(d.status == .prohibited)
        #expect(d.enforcement == .hardBlock)
        #expect(d.ruleVersion == 1)
        #expect(d.ruleKey == "ncaa.d1.basketball.mens.coach.electronic_correspondence")
        #expect(d.sourceLink?.host() == "web3.ncaa.org")
        #expect(d.sourceReference?.hasPrefix("Bylaw 13.4.1.5") == true)
        #expect(d.effectiveFrom == "2026-08-01")
        #expect(d.lastVerifiedDate != nil)
        #expect(d.missingContext.isEmpty)
        #expect(d.isVerifiedContext == false)
    }

    @Test("Needs-review decision decodes with nulls and missing context")
    func decodesNeedsReview() throws {
        let d = try Self.decode(Self.needsReviewJSON)
        #expect(d.status == .needsReview)
        #expect(d.enforcement == .none)
        #expect(d.ruleId == nil)
        #expect(d.sourceLink == nil)
        #expect(d.missingContext == ["athlete.sport_gender"])
        #expect(d.nextPermittedDate == nil)
    }

    @Test("Unknown status from a newer backend fails to decode (fail closed → unavailable)")
    func unknownStatusFails() {
        let json = Self.prohibitedJSON.replacingOccurrences(of: "\"prohibited\"", with: "\"maybe\"")
        #expect(throws: (any Error).self) { try Self.decode(json) }
    }

    // MARK: Presentation

    @Test("Next-permitted date renders as the rule's calendar day, not the device's")
    func nextPermittedDisplayUsesRuleCalendar() throws {
        let d = try Self.decode(Self.prohibitedJSON)
        // 04:00Z is June 14 in US Pacific time; the rule's day is June 15.
        #expect(d.nextPermittedDisplay?.contains("15") == true)
        #expect(d.nextPermittedDisplay?.contains("2027") == true)
        #expect(d.nextPermittedDate == "2027-06-15T04:00:00Z".asDate())
    }

    @Test("Badge labels use plain words per status")
    func badgeLabels() {
        #expect(Self.decision(status: .permitted).badgeLabel == "Allowed")
        #expect(Self.decision(status: .prohibited, next: "2027-06-15T04:00:00Z").badgeLabel == "Not yet")
        #expect(Self.decision(status: .prohibited).badgeLabel == "Not allowed")
        #expect(Self.decision(status: .permittedWithRestrictions).badgeLabel == "Allowed, with limits")
        #expect(Self.decision(status: .needsReview).badgeLabel == "Needs review")
    }

    @Test("Missing-context hints only point at things the athlete can fix")
    func missingContextHints() {
        #expect(Self.decision(status: .needsReview, missing: ["athlete.sport_gender"]).missingContextHint?.contains("boys/girls") == true)
        #expect(Self.decision(status: .needsReview, missing: ["athlete.grad_year"]).missingContextHint?.contains("graduation year") == true)
        #expect(Self.decision(status: .needsReview, missing: ["athlete.sophomore_completed_on"]).missingContextHint?.contains("sophomore year ended") == true)
        // Rule/program gaps are the server's to explain, not the athlete's to fix.
        #expect(Self.decision(status: .needsReview, missing: ["rule"]).missingContextHint == nil)
        #expect(Self.decision(status: .needsReview, missing: ["program.division"]).missingContextHint == nil)
        #expect(Self.decision(status: .needsReview, missing: ["coach.verified_program"]).missingContextHint == nil)
    }

    @Test("Source meta line shows effective date, last verified, and version")
    func sourceMetaLine() throws {
        let d = try Self.decode(Self.prohibitedJSON)
        let line = RecruitingRuleSourceView.metaLine(for: d)
        #expect(line?.contains("In effect since") == true)
        #expect(line?.contains("Last verified") == true)
        #expect(line?.contains("Rule v1") == true)
        #expect(RecruitingRuleSourceView.metaLine(for: try Self.decode(Self.needsReviewJSON)) == nil)
    }

    @Test("Action taxonomy raw values match the backend action_type strings")
    func actionRawValues() {
        #expect(RecruitingAction.coachSendRecruitingElectronicCorrespondence.rawValue == "coach_send_recruiting_electronic_correspondence")
        #expect(RecruitingAction.athleteSendIntroMessage.rawValue == "athlete_send_intro_message")
        #expect(RecruitingAction.coachOffCampusContact.rawValue == "coach_off_campus_contact")
        // Actions are distinct: one decision never stands in for another.
        #expect(Set(RecruitingAction.allCases.map(\.rawValue)).count == RecruitingAction.allCases.count)
    }

    // MARK: Cache

    @Test("Cache returns entries within lifetime and drops them after")
    func cacheLifetime() {
        var cache = RecruitingDecisionCache(lifetime: 600)
        let key = RecruitingDecisionCache.Key(athleteId: "a", action: .coachSendRecruitingElectronicCorrespondence, governingBody: "NCAA", division: "D1")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let d = Self.decision(status: .permitted)

        #expect(cache.decision(for: key, now: t0) == nil)
        cache.store(d, for: key, now: t0)
        #expect(cache.decision(for: key, now: t0.addingTimeInterval(599)) == d)
        #expect(cache.decision(for: key, now: t0.addingTimeInterval(600)) == nil)

        // Different inputs never share an entry.
        let otherDivision = RecruitingDecisionCache.Key(athleteId: "a", action: .coachSendRecruitingElectronicCorrespondence, governingBody: "NCAA", division: "D2")
        let otherAction = RecruitingDecisionCache.Key(athleteId: "a", action: .athleteSendIntroMessage, governingBody: "NCAA", division: "D1")
        #expect(cache.decision(for: otherDivision, now: t0) == nil)
        #expect(cache.decision(for: otherAction, now: t0) == nil)

        cache.removeAll()
        #expect(cache.decision(for: key, now: t0) == nil)
    }

    // MARK: Server error mapping

    @Test("RECRUITING_ACTION_PROHIBITED maps to a typed error with the server's message")
    func mapsProhibitedError() {
        let pg = PostgrestError(
            details: Self.prohibitedJSON,
            hint: "hint text",
            code: "P0001",
            message: "RECRUITING_ACTION_PROHIBITED"
        )
        let mapped = RecruitingRulesError.fromServerError(pg)
        guard case .actionProhibited(let message, let decision)? = mapped else {
            Issue.record("expected actionProhibited, got \(String(describing: mapped))")
            return
        }
        #expect(message.contains("June 15"))
        #expect(decision?.status == .prohibited)
        #expect(decision?.ruleVersion == 1)
        #expect(mapped?.userMessage == message)
    }

    @Test("Prohibited error without parseable detail falls back to the hint, then a default")
    func mapsProhibitedErrorFallbacks() {
        let withHint = RecruitingRulesError.fromServerError(
            PostgrestError(details: "not json", hint: "Use the hint", message: "RECRUITING_ACTION_PROHIBITED")
        )
        #expect(withHint?.userMessage == "Use the hint")

        let bare = RecruitingRulesError.fromServerError(PostgrestError(message: "RECRUITING_ACTION_PROHIBITED"))
        #expect(bare?.userMessage == RecruitingRulesError.defaultProhibitedMessage)
    }

    @Test("Other errors are not recruiting errors")
    func ignoresOtherErrors() {
        #expect(RecruitingRulesError.fromServerError(PostgrestError(message: "This conversation is blocked. Unblock to send messages.")) == nil)
        #expect(RecruitingRulesError.fromServerError(URLError(.notConnectedToInternet)) == nil)
    }

    // MARK: No rule authority in the client

    @Test("Compliance keeps only reference material and non-rule notes")
    func complianceHasNoDates() {
        // Notes for divisions without engine rules are orientation copy, not rules.
        #expect(Compliance.divisionsWithoutEngineRules == ["D3", "NAIA", "JUCO"])
        for division in Compliance.divisionsWithoutEngineRules {
            #expect(Compliance.divisionNote(division) != nil)
        }
        #expect(Compliance.divisionNote("D1") == nil)
        #expect(Compliance.divisionNote("D2") == nil)
        #expect(!Compliance.athleteOutreachNote.contains("June"))
        #expect(!Compliance.rulesEngineDisclaimer.contains("June"))
    }
}
