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
}
