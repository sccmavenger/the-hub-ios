import Foundation

struct AthleteInvite: Codable, Identifiable {
    let id: String
    let athleteId: String
    let code: String
    var invitedEmail: String?
    var relationship: String?
    var redeemedAt: String?
    var redeemedBy: String?
    let expiresAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case code
        case invitedEmail = "invited_email"
        case relationship
        case redeemedAt = "redeemed_at"
        case redeemedBy = "redeemed_by"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    var isRedeemed: Bool { redeemedAt != nil }
}
