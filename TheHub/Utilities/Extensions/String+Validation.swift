import Foundation

extension String {
    var isValidEmail: Bool {
        let regex = /^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$/
        return self.wholeMatch(of: regex) != nil
    }

    // Must match the Supabase auth setting (password_min_length = 8)
    var isValidPassword: Bool {
        count >= 8
    }

    /// Strips whitespace and newlines from both ends.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }
}
