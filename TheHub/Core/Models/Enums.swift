import SwiftUI

enum AppRole: String, Codable, CaseIterable {
    case admin
    case coach
    case athlete
    case parent

    var displayName: String {
        switch self {
        case .admin: "Admin"
        case .coach: "Coach"
        case .athlete: "Athlete"
        case .parent: "Parent / Guardian"
        }
    }
}

enum CoachRequestStatus: String, Codable {
    case pending
    case approved
    case rejected
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

enum SportGender: String, Codable, CaseIterable {
    case mens
    case womens

    var displayName: String {
        switch self {
        case .mens: "Men's"
        case .womens: "Women's"
        }
    }
}
