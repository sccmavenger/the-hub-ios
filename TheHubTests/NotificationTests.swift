import Foundation
import Testing
@testable import TheHub

/// Notifications center client contract (spec §14, D28). Delivery, read
/// ownership and alert dedupe are tested in SQL (notifications-alerts.test.sql);
/// these cover decoding of the typed destinations the server writes.
@Suite("Notifications — client")
struct NotificationTests {

    private func decode(_ destination: String) throws -> AppNotification {
        let json = """
        {"id":"n1","user_id":"u1","title":"T","body":"B","type":"message","link":"/messages",
         "destination":\(destination),"read_at":null,"created_at":"2026-10-01T12:00:00Z"}
        """
        return try JSONDecoder().decode(AppNotification.self, from: Data(json.utf8))
    }

    @Test("Thread and saved-search destinations carry their ids")
    func typedDestinations() throws {
        let thread = try decode(#"{"type":"thread","athlete_id":"a1","coach_user_id":"c1"}"#)
        #expect(thread.destination == .thread(athleteId: "a1", coachUserId: "c1"))

        let saved = try decode(#"{"type":"saved_search","saved_search_id":"s1","program_id":"p1"}"#)
        #expect(saved.destination == .savedSearch(id: "s1", programId: "p1"))

        let athlete = try decode(#"{"type":"athlete","athlete_id":"a9"}"#)
        #expect(athlete.destination == .athlete(athleteId: "a9"))
        #expect(athlete.destination?.isNavigable == true)
    }

    @Test("Unknown or incomplete destinations decode as non-navigable, never fail the row")
    func unknownDestination() throws {
        let future = try decode(#"{"type":"something_new"}"#)
        #expect(future.destination == .unknown(type: "something_new"))
        #expect(future.destination?.isNavigable == false)

        let incomplete = try decode(#"{"type":"thread","athlete_id":"a1"}"#)
        #expect(incomplete.destination == .unknown(type: "thread"))

        let missing = try decode("null")
        #expect(missing.destination == nil)
        #expect(missing.title == "T")
    }

    @Test("Read state and row symbol follow the server fields")
    func readStateAndSymbol() throws {
        var n = try decode(#"{"type":"messages"}"#)
        #expect(!n.isRead)
        #expect(n.symbolName == "message.fill")
        n.readAt = "2026-10-01T13:00:00Z"
        #expect(n.isRead)

        let json = """
        {"id":"n2","user_id":"u1","title":"Approved","type":"coach_application_approved","created_at":"2026-10-01T12:00:00Z"}
        """
        let coach = try JSONDecoder().decode(AppNotification.self, from: Data(json.utf8))
        #expect(coach.symbolName == "checkmark.seal.fill")
        #expect(coach.destination == nil)
    }
}
