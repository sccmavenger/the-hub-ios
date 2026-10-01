import Foundation
import Testing
@testable import TheHub

@Suite("ICS schedule import")
struct ICSParserTests {

    static let sample = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//School//Athletics//EN
    BEGIN:VEVENT
    UID:1
    DTSTART;VALUE=DATE:20261003
    SUMMARY:MICDS vs. Ladue
    LOCATION:MICDS Gym\\, 101 N Warson Rd\\, St. Louis
    END:VEVENT
    BEGIN:VEVENT
    UID:2
    DTSTART;TZID=America/Chicago:20261010T190000
    SUMMARY:Varsity Basketball @ CBC (Away)
    LOCATION:CBC High School
    END:VEVENT
    BEGIN:VEVENT
    UID:3
    DTSTART:20261017T001500Z
    SUMMARY:Boys Varsity at Chaminade
     — Conference
    END:VEVENT
    BEGIN:VEVENT
    UID:4
    SUMMARY:No start date, skipped
    END:VEVENT
    END:VCALENDAR
    """

    @Test("Parses all-day, zoned and UTC starts; skips events without DTSTART")
    func parsesEvents() {
        let events = ICSParser.parse(Self.sample)
        #expect(events.count == 3)

        #expect(events[0].date == "2026-10-03")
        #expect(events[0].time == nil)
        #expect(events[0].opponent == "Ladue")
        #expect(events[0].location == "MICDS Gym, 101 N Warson Rd, St. Louis", "escaped commas unescaped")

        #expect(events[1].date == "2026-10-10")
        #expect(events[1].time != nil)
        #expect(events[1].opponent == "CBC", "parenthetical dropped")
        #expect(events[1].location == "CBC High School")

        // Folded continuation line joined into the summary.
        #expect(events[2].summary.hasPrefix("Boys Varsity at Chaminade"))
        #expect(events[2].opponent?.hasPrefix("Chaminade") == true)
    }

    @Test("Opponent heuristics handle common schedule phrasings")
    func opponentHeuristics() {
        #expect(ICSParser.opponent(from: "MICDS vs Ladue") == "Ladue")
        #expect(ICSParser.opponent(from: "@ Ladue") == "Ladue")
        #expect(ICSParser.opponent(from: "@Ladue") == "Ladue")
        #expect(ICSParser.opponent(from: "Varsity at CBC") == "CBC")
        #expect(ICSParser.opponent(from: "Advance Prep Tournament") == "Advance Prep Tournament", "no false 'at' match inside a word")
        #expect(ICSParser.opponent(from: "   ") == nil)
    }

    @Test("Line unfolding and property splitting follow RFC 5545")
    func unfoldAndSplit() {
        let lines = ICSParser.unfold("SUMMARY:Long\r\n  title\r\nLOCATION:Gym")
        #expect(lines == ["SUMMARY:Long title", "LOCATION:Gym"])

        let parsed = ICSParser.split("DTSTART;TZID=\"America/Chicago\":20261003T190000")
        #expect(parsed?.0 == "DTSTART")
        #expect(parsed?.1["TZID"] == "America/Chicago")
        #expect(parsed?.2 == "20261003T190000")
    }

    @Test("Date-only values never shift a day regardless of zone")
    func dateOnlyIsStable() {
        let result = ICSParser.dateAndTime("20261225", params: ["VALUE": "DATE"])
        #expect(result?.0 == "2026-12-25")
        #expect(result?.1 == nil)
        #expect(ICSParser.dateAndTime("garbage", params: [:]) == nil)
    }
}
