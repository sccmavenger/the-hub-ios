import Foundation

struct AthleteVideo: Codable, Identifiable {
    let id: String
    let athleteId: String
    let url: String
    var title: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case url
        case title
        case createdAt = "created_at"
    }
}
