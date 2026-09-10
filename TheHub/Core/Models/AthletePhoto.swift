import Foundation

struct AthletePhoto: Codable, Identifiable {
    let id: String
    let athleteId: String
    let url: String
    var caption: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case url
        case caption
        case createdAt = "created_at"
    }
}
