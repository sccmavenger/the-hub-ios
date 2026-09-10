import Foundation

struct AthleteGuardian: Codable, Identifiable {
    let id: String
    let athleteId: String
    let userId: String
    var relationship: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case userId = "user_id"
        case relationship
        case createdAt = "created_at"
    }
}
