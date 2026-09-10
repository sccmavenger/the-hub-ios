import Foundation

struct AthleteCollegeInterest: Codable, Identifiable {
    let id: String
    let athleteId: String
    var collegeName: String
    var division: String?
    var state: String?
    var status: String
    var notes: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case collegeName = "college_name"
        case division
        case state
        case status
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var collegeStatus: CollegeStatus {
        CollegeStatus(rawValue: status) ?? .interested
    }
}
