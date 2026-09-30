import SwiftUI

enum AppRole: String, Codable, CaseIterable {
    case admin
    case coach
    case athlete
    case parent

    var displayName: String {
        switch self {
        case .admin: "Admin"
        // "College" is deliberate: the coach role is college-recruiting access.
        // HS/club coaches and trainers are not this path.
        case .coach: "College Coach"
        case .athlete: "Athlete"
        case .parent: "Parent / Guardian"
        }
    }
}

/// Mirrors the `coach_requests.status` check constraint (supabase/014).
/// nonisolated: used by the nonisolated CoachRequest model (decoded off-main).
nonisolated enum CoachRequestStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
    case withdrawn
    case needsMoreInformation = "needs_more_information"

    var displayName: String {
        switch self {
        case .pending: "Pending review"
        case .approved: "Approved"
        case .rejected: "Needs attention"
        case .withdrawn: "Withdrawn"
        case .needsMoreInformation: "More information needed"
        }
    }
}

/// Athletics governing bodies a coach may claim. Stored as the raw value in
/// `coach_requests.governing_body` / `recruiting_programs.governing_body`;
/// the rules engine keys rules on the same strings.
nonisolated enum GoverningBody: String, Codable, CaseIterable, Identifiable, Sendable {
    case ncaa = "NCAA"
    case naia = "NAIA"
    case njcaa = "NJCAA"
    case other = "Other"
    case unknown = "Unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ncaa: "NCAA"
        case .naia: "NAIA"
        case .njcaa: "NJCAA (junior college)"
        case .other: "Other"
        case .unknown: "Not sure"
        }
    }

    /// Bodies whose programs are organized into numbered divisions. NAIA
    /// basketball is a single division; "Other"/"Not sure" take free text.
    var hasNumberedDivisions: Bool {
        self == .ncaa || self == .njcaa
    }

    static let numberedDivisions = ["D1", "D2", "D3"]

    /// "NCAA Division I" — for status/program cards.
    static func divisionLabel(governingBody: String?, division: String?) -> String? {
        guard let governingBody, !governingBody.isEmpty, governingBody != GoverningBody.unknown.rawValue else {
            return nil
        }
        guard let division, !division.isEmpty else { return governingBody }
        let roman: String
        switch division {
        case "D1": roman = "Division I"
        case "D2": roman = "Division II"
        case "D3": roman = "Division III"
        default: roman = division
        }
        return "\(governingBody) \(roman)"
    }
}

enum PipelineStage: String, Codable, CaseIterable {
    case watching
    case evaluating
    case contacted
    case offered
    case passed

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .watching: .blue
        case .evaluating: .purple
        case .contacted: .orange
        case .offered: .green
        case .passed: .gray
        }
    }
}

enum CollegeStatus: String, Codable, CaseIterable {
    case interested
    case applied
    case contacted
    case visiting
    case offered
    case committed

    var displayName: String {
        rawValue.capitalized
    }
}

nonisolated enum SportGender: String, Codable, CaseIterable, Sendable {
    case mens
    case womens

    var displayName: String {
        switch self {
        case .mens: "Men's"
        case .womens: "Women's"
        }
    }

    /// Athlete-facing label — the field picks which basketball program /
    /// NCAA recruiting calendar applies, so it reads "Boys / Girls" (web parity).
    var basketballLabel: String {
        switch self {
        case .mens: "Boys"
        case .womens: "Girls"
        }
    }
}
