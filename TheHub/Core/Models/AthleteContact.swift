import Foundation

struct AthleteContact: Codable, Identifiable {
    let id: String
    let athleteId: String
    var athleteEmail: String?
    var athletePhone: String?
    var guardianName: String?
    var guardianEmail: String?
    var guardianPhone: String?
    var clubCoachName: String?
    var clubCoachPhone: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case athleteEmail = "athlete_email"
        case athletePhone = "athlete_phone"
        case guardianName = "guardian_name"
        case guardianEmail = "guardian_email"
        case guardianPhone = "guardian_phone"
        case clubCoachName = "club_coach_name"
        case clubCoachPhone = "club_coach_phone"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
