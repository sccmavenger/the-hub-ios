import Foundation
import Testing
import Supabase
@testable import TheHub

/// Client-side tests for coach onboarding (spec §35, §40). Authorization,
/// approval atomicity and RLS are tested in SQL
/// (supabase/tests/coach-onboarding.test.sql); these cover the app's side of
/// the contract: the signup metadata the trigger expects, faithful decoding
/// of `coach_requests`, and account-state routing.
@Suite("Coach onboarding — client")
struct CoachOnboardingTests {

    // MARK: - Signup metadata contract (supabase/014 handle_new_user)

    @Test("Coach signup metadata carries every claim under the trigger's keys")
    func coachSignupMetadata() {
        let application = AuthService.CoachApplication(
            fullName: "Test Coach",
            title: "Assistant Coach",
            institution: "Test University",
            governingBody: .ncaa,
            division: "D1",
            sportGender: .mens,
            athleticsUrl: "https://athletics.example.test/staff",
            programUrl: "https://athletics.example.test/mbb",
            phone: "555-0100",
            note: "Listed on the staff page."
        )
        let data = application.signupMetadata

        #expect(data["signup_role"] == .string("coach"))
        #expect(data["full_name"] == .string("Test Coach"))
        #expect(data["coach_title"] == .string("Assistant Coach"))
        #expect(data["institution"] == .string("Test University"))
        #expect(data["governing_body"] == .string("NCAA"))
        #expect(data["division"] == .string("D1"))
        #expect(data["sport_gender"] == .string("mens"))
        #expect(data["athletics_url"] == .string("https://athletics.example.test/staff"))
        #expect(data["program_url"] == .string("https://athletics.example.test/mbb"))
        #expect(data["phone"] == .string("555-0100"))
        #expect(data["verification_note"] == .string("Listed on the staff page."))
    }

    @Test("Coach signup metadata never claims a status, role or verification")
    func coachSignupMetadataHasNoAuthorizationKeys() {
        let application = AuthService.CoachApplication(
            fullName: "Test Coach", title: "Head Coach", institution: "Test College",
            governingBody: .naia, division: nil, sportGender: .womens,
            athleticsUrl: nil, programUrl: nil, phone: nil, note: nil
        )
        let keys = Set(application.signupMetadata.keys)

        #expect(!keys.contains("status"))
        #expect(!keys.contains("role"))
        #expect(!keys.contains("user_roles"))
        #expect(!keys.contains("verified_at"))
        #expect(!keys.contains("division"), "NAIA basketball has no division; nil must be omitted, not sent as empty")
        #expect(!keys.contains("athletics_url"))
        #expect(keys == ["signup_role", "full_name", "coach_title", "institution", "governing_body", "sport_gender"])
    }

    @Test("Blank optional fields are omitted from metadata")
    func blankOptionalsOmitted() {
        let application = AuthService.CoachApplication(
            fullName: "Test Coach", title: "Coach", institution: "U",
            governingBody: .other, division: "  ", sportGender: .mens,
            athleticsUrl: "", programUrl: "   ", phone: "", note: "\n"
        )
        let keys = Set(application.signupMetadata.keys)
        #expect(!keys.contains("division"))
        #expect(!keys.contains("athletics_url"))
        #expect(!keys.contains("program_url"))
        #expect(!keys.contains("phone"))
        #expect(!keys.contains("verification_note"))
    }

    // MARK: - coach_requests decoding

    static let pendingRequestJSON = """
    {
      "id": "11111111-1111-4111-8111-111111111111",
      "user_id": "22222222-2222-4222-8222-222222222222",
      "full_name": "Test Coach",
      "email": "coach@athletics.example.test",
      "title": "Assistant Coach",
      "college": "Test University",
      "message": null,
      "status": "pending",
      "reviewed_at": null,
      "reviewed_by": null,
      "created_at": "2026-09-30T18:00:00+00:00",
      "governing_body": "NCAA",
      "division": "D1",
      "sport": "basketball",
      "sport_gender": "mens",
      "athletics_url": null,
      "program_url": "https://athletics.example.test/mbb",
      "phone": null,
      "rejection_reason": null,
      "info_request_message": null,
      "resubmitted_at": null,
      "approved_program_id": null,
      "approved_membership_id": null,
      "updated_at": "2026-09-30T18:00:00+00:00"
    }
    """

    @Test("Decodes a pending request and derives display labels")
    func decodesPendingRequest() throws {
        let request = try JSONDecoder().decode(CoachRequest.self, from: Data(Self.pendingRequestJSON.utf8))
        #expect(request.status == .pending)
        #expect(request.isEditable)
        #expect(request.programLabel == "Men's Basketball")
        #expect(request.divisionLabel == "NCAA Division I")
        #expect(request.approvedProgramId == nil)
    }

    @Test("Decodes every status the check constraint allows")
    func decodesAllStatuses() throws {
        for (raw, expected): (String, CoachRequestStatus) in [
            ("pending", .pending), ("approved", .approved), ("rejected", .rejected),
            ("withdrawn", .withdrawn), ("needs_more_information", .needsMoreInformation)
        ] {
            let json = Self.pendingRequestJSON.replacingOccurrences(of: "\"status\": \"pending\"", with: "\"status\": \"\(raw)\"")
            let request = try JSONDecoder().decode(CoachRequest.self, from: Data(json.utf8))
            #expect(request.status == expected, "status \(raw)")
            #expect(request.isEditable == (expected != .approved), "editability for \(raw)")
        }
    }

    @Test("Division label handles non-NCAA and unknown claims without guessing")
    func divisionLabels() {
        #expect(GoverningBody.divisionLabel(governingBody: "NCAA", division: "D3") == "NCAA Division III")
        #expect(GoverningBody.divisionLabel(governingBody: "NJCAA", division: "D2") == "NJCAA Division II")
        #expect(GoverningBody.divisionLabel(governingBody: "NAIA", division: nil) == "NAIA")
        #expect(GoverningBody.divisionLabel(governingBody: "Other", division: "Club") == "Other Club")
        #expect(GoverningBody.divisionLabel(governingBody: "Unknown", division: nil) == nil)
        #expect(GoverningBody.divisionLabel(governingBody: nil, division: "D1") == nil)
    }

    @Test("College Coach is the signup-facing label; the role value stays 'coach'")
    func coachRoleLabel() {
        #expect(AppRole.coach.displayName == "College Coach")
        #expect(AppRole.coach.rawValue == "coach")
    }

    // MARK: - Shared claims form

    @Test("Claims round-trip from a request and produce an explicit-null RPC payload")
    func claimsFromRequest() throws {
        var request = try JSONDecoder().decode(CoachRequest.self, from: Data(Self.pendingRequestJSON.utf8))
        request.athleticsUrl = nil
        let claims = CoachProgramClaims(from: request)

        #expect(claims.title == "Assistant Coach")
        #expect(claims.institution == "Test University")
        #expect(claims.sportGender == .mens)
        #expect(claims.governingBody == .ncaa)
        #expect(claims.numberedDivision == "D1")
        #expect(claims.isComplete)

        let payload = claims.rpcPayload
        #expect(payload["governing_body"] == .string("NCAA"))
        #expect(payload["division"] == .string("D1"))
        #expect(payload["athletics_url"] == .null, "cleared fields are sent as null so the server clears them")
        #expect(payload["program_url"] == .string("https://athletics.example.test/mbb"))
        #expect(payload.keys.contains("status") == false)
    }

    @Test("NCAA claims are incomplete without a division; NAIA needs none")
    func claimsCompleteness() {
        var claims = CoachProgramClaims()
        claims.title = "Head Coach"
        claims.institution = "Test College"
        claims.sportGender = .womens
        claims.governingBody = .ncaa
        #expect(!claims.isComplete)
        claims.numberedDivision = "D2"
        #expect(claims.isComplete)
        #expect(claims.division == "D2")

        claims.governingBody = .naia
        #expect(claims.isComplete)
        #expect(claims.division == nil, "NAIA basketball is a single division")

        claims.governingBody = .other
        claims.divisionText = "Club"
        #expect(claims.division == "Club")
    }

    @Test("Bare hostnames get https; empty stays nil")
    func urlNormalization() {
        #expect(CoachProgramClaims.normalizedURL("athletics.example.test/staff") == "https://athletics.example.test/staff")
        #expect(CoachProgramClaims.normalizedURL("HTTP://x.test") == "HTTP://x.test")
        #expect(CoachProgramClaims.normalizedURL("   ") == nil)
    }

    // MARK: - Account-state routing (spec §16, §40)

    private func request(status: CoachRequestStatus) throws -> CoachRequest {
        let json = Self.pendingRequestJSON.replacingOccurrences(
            of: "\"status\": \"pending\"", with: "\"status\": \"\(status.rawValue)\""
        )
        return try JSONDecoder().decode(CoachRequest.self, from: Data(json.utf8))
    }

    @Test("Roles route by precedence regardless of any coach application")
    func rolesTakePrecedence() throws {
        let pending = try request(status: .pending)
        #expect(AccountStateResolver.route(roles: [.athlete], roleLoadFailed: false, coachRequest: .notLoaded) == .athlete)
        #expect(AccountStateResolver.route(roles: [.parent], roleLoadFailed: false, coachRequest: .loaded(pending)) == .parent)
        #expect(AccountStateResolver.route(roles: [.coach], roleLoadFailed: false, coachRequest: .loaded(pending)) == .coach)
        #expect(AccountStateResolver.route(roles: [.admin, .coach], roleLoadFailed: false, coachRequest: .notLoaded) == .admin)
        #expect(AccountStateResolver.route(roles: [.parent, .athlete], roleLoadFailed: false, coachRequest: .failed) == .athlete)
    }

    @Test("Each application status has its own route; approved-without-role means paused")
    func applicationStatusRoutes() throws {
        for (status, expected): (CoachRequestStatus, (CoachRequest) -> AccountRoute) in [
            (.pending, AccountRoute.coachPending),
            (.needsMoreInformation, AccountRoute.coachNeedsInformation),
            (.rejected, AccountRoute.coachRejected),
            (.withdrawn, AccountRoute.coachWithdrawn),
            (.approved, AccountRoute.coachAccessPaused)
        ] {
            let r = try request(status: status)
            #expect(
                AccountStateResolver.route(roles: [], roleLoadFailed: false, coachRequest: .loaded(r)) == expected(r),
                "status \(status.rawValue)"
            )
        }
    }

    @Test("Nil role is not treated as coach-pending")
    func nilRoleIsNotPending() {
        #expect(AccountStateResolver.route(roles: [], roleLoadFailed: false, coachRequest: .notLoaded) == .loading)
        #expect(AccountStateResolver.route(roles: [], roleLoadFailed: false, coachRequest: .loaded(nil)) == .accountConfigurationError)
        #expect(AccountStateResolver.route(roles: [], roleLoadFailed: true, coachRequest: .notLoaded) == .roleLoadError)
        #expect(AccountStateResolver.route(roles: [], roleLoadFailed: false, coachRequest: .failed) == .roleLoadError)
    }

    @Test("A role fetch failure never overrides cached roles")
    func roleFailureKeepsCachedRoles() {
        #expect(AccountStateResolver.route(roles: [.athlete], roleLoadFailed: true, coachRequest: .failed) == .athlete)
    }

    // MARK: - Program / membership models (admin + Coach Mode)

    static let membershipWithProgramJSON = """
    {
      "id": "33333333-3333-4333-8333-333333333333",
      "coach_user_id": "22222222-2222-4222-8222-222222222222",
      "program_id": "44444444-4444-4444-8444-444444444444",
      "title": "Assistant Coach",
      "membership_role": "assistant_coach",
      "status": "verified",
      "verified_at": "2026-09-30T19:00:00+00:00",
      "verified_by": "55555555-5555-4555-8555-555555555555",
      "started_at": "2026-09-30",
      "ended_at": null,
      "created_at": "2026-09-30T19:00:00+00:00",
      "updated_at": "2026-09-30T19:00:00+00:00",
      "recruiting_programs": {
        "id": "44444444-4444-4444-8444-444444444444",
        "institution_name": "Test University",
        "normalized_institution_name": "test university",
        "governing_body": "NCAA",
        "division": "D1",
        "sport": "basketball",
        "sport_gender": "womens",
        "athletics_url": null,
        "program_url": null,
        "official_url": null,
        "active": true,
        "verified_at": "2026-09-30T19:00:00+00:00",
        "verified_by": "55555555-5555-4555-8555-555555555555",
        "created_at": "2026-09-30T19:00:00+00:00",
        "updated_at": "2026-09-30T19:00:00+00:00"
      }
    }
    """

    @Test("Decodes a membership with its embedded program")
    func decodesMembershipWithProgram() throws {
        let membership = try JSONDecoder().decode(CoachProgramMembership.self, from: Data(Self.membershipWithProgramJSON.utf8))
        #expect(membership.status == .verified)
        #expect(membership.roleDisplayName == "Assistant Coach")
        let program = try #require(membership.program)
        #expect(program.isVerified)
        #expect(program.fullLabel == "Test University Women's Basketball")
        #expect(program.divisionLabel == "NCAA Division I")
    }

    @Test("New-program payload for approval carries only confirmed attributes")
    func newProgramPayload() {
        let program = CoachAdminService.NewProgram(
            institutionName: " Test University ", governingBody: .ncaa, division: "D2",
            sportGender: .mens, athleticsUrl: nil, programUrl: ""
        )
        guard case .object(let object) = program.json else {
            Issue.record("expected object")
            return
        }
        #expect(object["institution_name"] == .string("Test University"))
        #expect(object["governing_body"] == .string("NCAA"))
        #expect(object["division"] == .string("D2"))
        #expect(object["sport"] == .string("basketball"))
        #expect(object["sport_gender"] == .string("mens"))
        #expect(object["athletics_url"] == nil)
        #expect(object["program_url"] == nil)
        #expect(object["verified_at"] == nil, "verification is the server's call")
    }
}
