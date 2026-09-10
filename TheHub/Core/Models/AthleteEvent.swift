import Foundation

struct AthleteEvent: Codable, Identifiable {
    let id: String
    let athleteId: String
    var eventDate: String
    var eventTime: String?
    var opponent: String?
    var location: String?
    var notes: String?
    // DB column is "is_mayb" (not a typo in the schema)
    var isMaybe: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case eventDate = "event_date"
        case eventTime = "event_time"
        case opponent
        case location
        case notes
        case isMaybe = "is_mayb"
        case createdAt = "created_at"
    }
}
