import Foundation

struct AthleteProfileView: Codable, Identifiable {
    let id: String
    let athleteId: String
    var viewerUserId: String?
    let viewerRole: String
    var viewerLabel: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case viewerUserId = "viewer_user_id"
        case viewerRole = "viewer_role"
        case viewerLabel = "viewer_label"
        case createdAt = "created_at"
    }
}
