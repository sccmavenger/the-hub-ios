import Foundation
import Testing
import Supabase
@testable import TheHub

/// Client side of the Coach Workspace data layer (spec §16). Authorization,
/// allowlisting and board rules are tested in SQL; these cover faithful
/// decoding of the RPC payloads, the program-selection rule, and the filter
/// encoding contract.
@Suite("Coach workspace — client")
struct CoachWorkspaceTests {

    static let cardJSON = """
    {"athlete_id":"a1","full_name":"Near Athlete","profile_photo_path":"u/profile.jpg","high_school":"CW High",
     "hometown":"St. Louis","state":"MO","grad_year":2027,"position":"Point Guard","jersey_number":"3",
     "height_inches":74,"weight_lbs":170,"gpa":3.6,"bio":null,"intended_major":null,"instagram_handle":"@near",
     "tiktok_handle":null,"sport_gender":"mens","is_published":true,"distance_miles":25}
    """

    @Test("Athlete card decodes the allowlist and derives display lines")
    func cardDecoding() throws {
        let card = try JSONDecoder().decode(CoachAthleteCard.self, from: Data(Self.cardJSON.utf8))
        #expect(card.heightDisplay == "6'2\"")
        #expect(card.classLabel == "Class of 2027")
        #expect(card.schoolLine == "CW High · St. Louis, MO")
        #expect(card.distanceMiles == 25)
        #expect(card.boardPipelineStage == nil)
    }

    @Test("Discover items decode the 018 board stage and next event date")
    func cardBoardStage() throws {
        let json = Self.cardJSON.replacingOccurrences(of: "\"distance_miles\":25}", with: "\"distance_miles\":25,\"board_stage\":\"evaluating\",\"next_event_date\":\"2026-10-04\"}")
        let card = try JSONDecoder().decode(CoachAthleteCard.self, from: Data(json.utf8))
        #expect(card.boardPipelineStage == .evaluating)
        #expect(card.nextEventDate == "2026-10-04")
    }

    @Test("Filter chips summarize each active group")
    func filterChips() {
        var f = DiscoverFilters()
        #expect(f.chipLabels.isEmpty)
        f.gradYears = [2028, 2027]
        f.positions = ["Guard"]
        f.zipCode = "63101"; f.centerLat = 1; f.centerLng = 1; f.radiusMiles = 100
        f.minHeightInches = 74
        f.minGpa = 3.5
        f.playingWithin = .weekend
        #expect(f.chipLabels == ["Guard", "'27 '28", "100 mi of 63101", "≥ 6'2\"", "GPA ≥ 3.5", "This weekend"])
        f.radiusMiles = nil
        f.states = ["MO", "IL"]
        #expect(f.chipLabels.contains("MO, IL"), "states shown when no radius")
    }

    @Test("Search page decodes items, total and an opaque cursor")
    func searchPage() throws {
        let json = """
        {"items":[\(Self.cardJSON)],"next_cursor":{"k":"near athlete","id":"a1"},"total":2,"program_id":"p1","sport_gender":"mens"}
        """
        let page = try JSONDecoder().decode(AthleteSearchPage.self, from: Data(json.utf8))
        #expect(page.items.count == 1 && page.total == 2 && page.hasMore)
        let last = """
        {"items":[],"next_cursor":null,"total":0,"program_id":"p1","sport_gender":"mens"}
        """
        let end = try JSONDecoder().decode(AthleteSearchPage.self, from: Data(last.utf8))
        #expect(!end.hasMore)
    }

    @Test("Detail decodes board state, contact lock and private note")
    func detailDecoding() throws {
        let json = """
        {"athlete":\(Self.cardJSON),
         "photos":[{"id":"ph1","storage_path":"u/gallery/x.jpg","caption":null,"created_at":"2026-10-01T00:00:00+00:00"}],
         "videos":[{"id":"v1","url":"https://youtu.be/x","title":"Highlights"}],
         "upcoming_events":[{"id":"e1","event_date":"2026-10-04","event_time":null,"opponent":"Rival","location":null,"notes":null,"is_mayb":false}],
         "contact_unlocked":true,
         "contact":{"athlete_email":"a@x.test","athlete_phone":null,"guardian_name":"G","guardian_email":null,"guardian_phone":"555","club_coach_name":null,"club_coach_phone":null},
         "board":{"id":"b1","program_id":"p1","athlete_id":"a1","stage":"evaluating","tags":["Shooter","Length"],"assigned_to":"c1","assigned_to_name":"Coach One","saved_by":"c2","saved_by_name":"Coach Two","removed_at":null,"created_at":"2026-10-01T00:00:00+00:00","updated_at":"2026-10-01T00:00:00+00:00"},
         "private_note":"Quiet leader.",
         "program_id":"p1"}
        """
        let detail = try JSONDecoder().decode(CoachAthleteDetail.self, from: Data(json.utf8))
        #expect(detail.contactUnlocked && detail.contact?.guardianPhone == "555")
        #expect(detail.board?.stage == .evaluating)
        #expect(detail.board?.tags == ["Shooter", "Length"])
        #expect(detail.board?.isRemoved == false)
        #expect(detail.privateNote == "Quiet leader.")
        #expect(detail.photos.first?.storagePath == "u/gallery/x.jpg")
    }

    @Test("Board page decodes stage counts and the list item shape")
    func boardPage() throws {
        let json = """
        {"items":[{"entry":{"id":"b1","program_id":"p1","athlete_id":"a1","stage":"watching","tags":[],"assigned_to":null,"assigned_to_name":null,"saved_by":"c1","saved_by_name":"Coach One","removed_at":null,"created_at":"2026-10-01T00:00:00+00:00","updated_at":"2026-10-01T00:00:00+00:00"},
                   "athlete":\(Self.cardJSON),"has_private_note":true}],
         "next_cursor":null,"stage_counts":{"watching":3,"offered":1},"assigned_to_me":2}
        """
        let page = try JSONDecoder().decode(BoardListPage.self, from: Data(json.utf8))
        #expect(page.items.first?.hasPrivateNote == true)
        #expect(page.count(for: .watching) == 3 && page.count(for: .passed) == 0 && page.total == 4)
        #expect(page.assignedToMe == 2)
    }

    @Test("Activity rows summarize in plain words")
    func activitySummary() throws {
        let json = """
        [{"id":"x1","entry_id":"b1","athlete_id":"a1","athlete_name":"Jordan","actor_user_id":"c1","actor_name":"Coach One",
          "action":"stage_changed","from_value":"watching","to_value":"evaluating","created_at":"2026-10-01T00:00:00+00:00"},
         {"id":"x2","entry_id":"b1","athlete_id":"a1","athlete_name":"Jordan","actor_user_id":"c1","actor_name":"Coach One",
          "action":"assigned","from_value":null,"to_value":"Coach Two","created_at":"2026-10-01T00:00:00+00:00"}]
        """
        let rows = try JSONDecoder().decode([BoardActivity].self, from: Data(json.utf8))
        #expect(rows[0].summary == "Coach One moved Jordan to Evaluating")
        #expect(rows[1].summary == "Coach One assigned Jordan to Coach Two")
    }

    @Test("Pipeline stages match the database check constraint")
    func stageRawValues() {
        #expect(PipelineStage.allCases.map(\.rawValue) == ["watching", "evaluating", "contacted", "offered", "passed"])
    }

    // MARK: - Program selection (spec §5.1, D16)

    private func context(_ programId: String, verifiedAt: String) -> CoachProgramContext {
        CoachProgramContext(
            membershipId: "m-\(programId)", coachUserId: "c1", programId: programId,
            institutionName: "U \(programId)", governingBody: "NCAA", division: "D1", sport: "basketball",
            sportGender: "mens", title: nil, membershipRole: nil, verifiedAt: verifiedAt
        )
    }

    @Test("A valid persisted choice wins; a lone program is implied; several with none means choose")
    func selectionRule() {
        let a = context("A", verifiedAt: "2026-09-01T00:00:00+00:00")
        let b = context("B", verifiedAt: "2026-10-01T00:00:00+00:00")   // newer
        #expect(CoachProgramContext.resolveSelection(persistedProgramId: "A", contexts: [a, b]) == a)
        #expect(CoachProgramContext.resolveSelection(persistedProgramId: "Z", contexts: [a, b]) == nil, "stale choice must not fall back to the newest")
        #expect(CoachProgramContext.resolveSelection(persistedProgramId: nil, contexts: [a, b]) == nil)
        #expect(CoachProgramContext.resolveSelection(persistedProgramId: nil, contexts: [a]) == a)
        #expect(CoachProgramContext.resolveSelection(persistedProgramId: "Z", contexts: [a]) == a)
        #expect(CoachProgramContext.resolveSelection(persistedProgramId: nil, contexts: []) == nil)
    }

    @Test("Chip label shortens the institution and names the gender")
    func chipLabel() {
        let c = CoachProgramContext(
            membershipId: "m", coachUserId: "c", programId: "p", institutionName: "University of IronMan",
            governingBody: "NCAA", division: "D1", sport: "basketball", sportGender: "mens",
            title: nil, membershipRole: nil, verifiedAt: nil
        )
        #expect(c.chipLabel == "IronMan · Men's")
    }

    // MARK: - Filters

    @Test("Discover filters round-trip through JSON with the saved-search keys")
    func filtersRoundTrip() throws {
        var f = DiscoverFilters()
        f.query = "jordan"
        f.positions = ["guard"]
        f.gradYears = [2027, 2028]
        f.zipCode = "63101"
        f.centerLat = 38.63
        f.centerLng = -90.20
        f.radiusMiles = 100
        f.minGpa = 3.5
        f.playingWithin = .next7Days
        let data = try JSONEncoder().encode(f)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys).isSuperset(of: ["query", "positions", "grad_years", "zip_code", "center_lat", "center_lng", "radius_miles", "min_gpa", "playing_within"]))
        let back = try JSONDecoder().decode(DiscoverFilters.self, from: data)
        #expect(back == f)
        #expect(back.activeCount == 6)
        #expect(back.hasRadius)
        #expect(DiscoverFilters().isEmpty)
    }
}
