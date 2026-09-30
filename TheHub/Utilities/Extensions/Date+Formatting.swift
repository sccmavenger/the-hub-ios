import Foundation

extension String {
    // Timestamps parse as instants (UTC) and display in local time.
    // Date-ONLY strings ("2026-09-18" — game dates, DOB) parse as LOCAL
    // midnight: parsing them as UTC made every date render a day early in
    // US timezones (Date.asDateOnlyString formats in local to match).
    private static let timestampFormatters: [ISO8601DateFormatter] = [
        {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }(),
        {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
    ]

    private static let dateOnlyFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()

    func asFormattedDate(style: DateFormatter.Style = .medium) -> String {
        guard let date = asDate() else { return self }
        let display = DateFormatter()
        display.dateStyle = style
        display.timeStyle = .none
        display.locale = .current
        return display.string(from: date)
    }

    func asDate() -> Date? {
        for formatter in Self.timestampFormatters {
            if let date = formatter.date(from: self) { return date }
        }
        return Self.dateOnlyFormatter.date(from: self)
    }
}

extension Date {
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isThisWeek: Bool { Calendar.current.isDate(self, equalTo: .now, toGranularity: .weekOfYear) }
}
