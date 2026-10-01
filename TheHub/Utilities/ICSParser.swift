import Foundation

/// Minimal iCalendar (.ics) reader for importing a team's game schedule
/// (TestFlight feedback 2026-09-30: "why can't I upload the ICS file?").
///
/// Reads VEVENT blocks only. Handles RFC 5545 line folding, DATE and
/// DATE-TIME values (floating, UTC `Z`, and `TZID=`), and derives an
/// opponent from the SUMMARY using common schedule phrasing
/// ("MICDS vs. Ladue", "@ Ladue", "at Ladue"). Everything else is ignored;
/// nothing here talks to the network or the database.
nonisolated enum ICSParser {
    nonisolated struct Event: Equatable, Sendable, Identifiable {
        /// yyyy-MM-dd in the event's own calendar day.
        let date: String
        /// "7:00 PM" style, nil for all-day events.
        let time: String?
        let summary: String
        let opponent: String?
        let location: String?

        var id: String { "\(date)|\(time ?? "")|\(summary)" }
    }

    /// Parses every VEVENT with a DTSTART. Order is by date, then time.
    static func parse(_ text: String) -> [Event] {
        let lines = unfold(text)
        var events: [Event] = []
        var current: [String: (params: [String: String], value: String)]?

        for line in lines {
            if line == "BEGIN:VEVENT" {
                current = [:]
                continue
            }
            if line == "END:VEVENT" {
                if let fields = current, let event = makeEvent(fields) {
                    events.append(event)
                }
                current = nil
                continue
            }
            guard current != nil, let (name, params, value) = split(line) else { continue }
            current?[name] = (params, value)
        }

        return events.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return ($0.time ?? "") < ($1.time ?? "")
        }
    }

    // MARK: - Pieces

    /// RFC 5545 §3.1: a line starting with a space or tab continues the previous one.
    static func unfold(_ text: String) -> [String] {
        var result: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            if let first = raw.first, first == " " || first == "\t", !result.isEmpty {
                result[result.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                result.append(raw)
            }
        }
        return result
    }

    /// "DTSTART;TZID=America/Chicago:20261003T190000" → ("DTSTART", ["TZID": "America/Chicago"], "20261003T190000")
    static func split(_ line: String) -> (String, [String: String], String)? {
        // The first ':' not inside a quoted parameter value ends the name/params.
        var inQuotes = false
        var colonIndex: String.Index?
        for index in line.indices {
            let ch = line[index]
            if ch == "\"" { inQuotes.toggle() }
            if ch == ":" && !inQuotes { colonIndex = index; break }
        }
        guard let colonIndex else { return nil }
        let head = String(line[..<colonIndex])
        let value = String(line[line.index(after: colonIndex)...])
        let parts = head.split(separator: ";", omittingEmptySubsequences: true).map(String.init)
        guard let name = parts.first?.uppercased(), !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                params[kv[0].uppercased()] = kv[1].replacingOccurrences(of: "\"", with: "")
            }
        }
        return (name, params, unescape(value))
    }

    /// RFC 5545 §3.3.11 text escapes.
    static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func makeEvent(_ fields: [String: (params: [String: String], value: String)]) -> Event? {
        guard let start = fields["DTSTART"], let (date, time) = dateAndTime(start.value, params: start.params) else { return nil }
        let summary = fields["SUMMARY"]?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location = fields["LOCATION"]?.value
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Event(
            date: date,
            time: time,
            summary: summary,
            opponent: opponent(from: summary),
            location: (location ?? "").isEmpty ? nil : location
        )
    }

    /// Returns the event's calendar day and, for timed events, a short local
    /// time. All-day `VALUE=DATE` entries have no time. UTC and `TZID` values
    /// are converted to the device's zone, since that's where the game is read.
    static func dateAndTime(_ value: String, params: [String: String], now: Date = .now) -> (String, String?)? {
        let digits = value.trimmingCharacters(in: .whitespaces)
        if params["VALUE"] == "DATE" || digits.count == 8 {
            guard digits.count == 8, digits.allSatisfy(\.isNumber) else { return nil }
            return ("\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))", nil)
        }
        // yyyyMMdd'T'HHmmss with optional trailing Z
        guard digits.count >= 15, digits[digits.index(digits.startIndex, offsetBy: 8)] == "T" else { return nil }
        let isUTC = digits.hasSuffix("Z")
        let core = isUTC ? String(digits.dropLast()) : digits
        guard core.count == 15 else { return nil }

        var components = DateComponents()
        components.year = Int(core.prefix(4))
        components.month = Int(core.dropFirst(4).prefix(2))
        components.day = Int(core.dropFirst(6).prefix(2))
        components.hour = Int(core.dropFirst(9).prefix(2))
        components.minute = Int(core.dropFirst(11).prefix(2))
        components.second = Int(core.dropFirst(13).prefix(2))

        var calendar = Calendar(identifier: .gregorian)
        if isUTC {
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        } else if let tzid = params["TZID"], let zone = TimeZone(identifier: tzid) {
            calendar.timeZone = zone
        } else {
            calendar.timeZone = .current   // floating time: as written, local
        }
        guard let instant = calendar.date(from: components) else { return nil }

        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd"
        let date = local.string(from: instant)
        return (date, instant.formatted(date: .omitted, time: .shortened))
    }

    /// "MICDS vs. Ladue" → "Ladue"; "@ Ladue" → "Ladue"; "Varsity at CBC" → "CBC";
    /// "Ladue" → "Ladue"; "" → nil. Trailing parentheticals like "(Away)" are kept
    /// out of the opponent since schedules often tack them on.
    static func opponent(from summary: String) -> String? {
        var text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Separator search is case-insensitive and word-bounded so "Advance" never matches " at ".
        let separators = [" vs. ", " vs ", " v. ", " v ", " at ", " @ ", "@ ", "@"]
        let lower = text.lowercased()
        for separator in separators {
            if let range = lower.range(of: separator) {
                let tail = text[range.upperBound...]
                text = String(tail)
                break
            } else if lower.hasPrefix(separator.trimmingCharacters(in: .whitespaces) + " ") {
                text = String(text.dropFirst(separator.trimmingCharacters(in: .whitespaces).count + 1))
                break
            }
        }
        if let paren = text.range(of: " (") {
            text = String(text[..<paren.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(60))
    }
}
