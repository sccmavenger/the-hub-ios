import Foundation

struct SearchFilters: Codable {
    var zipCode: String?
    var radius: Int?
    var position: String?
    var gradYear: Int?
    var minHeightInches: Int?
    var minGpa: Double?
    var sportGender: String?
    var playingWithinDays: Int?

    enum CodingKeys: String, CodingKey {
        case zipCode = "zip_code"
        case radius
        case position
        case gradYear = "grad_year"
        case minHeightInches = "min_height_inches"
        case minGpa = "min_gpa"
        case sportGender = "sport_gender"
        case playingWithinDays = "playing_within_days"
    }
}

struct CoachSavedSearch: Codable, Identifiable {
    let id: String
    let coachUserId: String
    var name: String
    var filters: SearchFilters
    var alertsEnabled: Bool
    var lastRunAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case coachUserId = "coach_user_id"
        case name
        case filters
        case alertsEnabled = "alerts_enabled"
        case lastRunAt = "last_run_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
