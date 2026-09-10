import Foundation

extension String {
    var isValidEmail: Bool {
        let regex = /^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$/
        return self.wholeMatch(of: regex) != nil
    }

    var isValidPassword: Bool {
        count >= 6
    }

    /// Strips whitespace and newlines from both ends.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }
}
