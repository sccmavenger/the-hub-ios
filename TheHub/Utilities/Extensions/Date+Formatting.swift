import Foundation

extension String {
    func asFormattedDate(style: DateFormatter.Style = .medium) -> String {
        let formatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withFullDate]
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: self) {
                let display = DateFormatter()
                display.dateStyle = style
                display.timeStyle = .none
                display.locale = .current
                return display.string(from: date)
            }
        }
        return self
    }

    func asDate() -> Date? {
        let formatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withFullDate]
                return f
            }()
        ]
        return formatters.compactMap { $0.date(from: self) }.first
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
