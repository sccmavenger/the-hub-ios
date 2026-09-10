import Foundation

struct CoachSavedAthlete: Codable, Identifiable {
    let id: String
    let coachUserId: String
    let athleteId: String
    var stage: String
    var tags: [String]
    var notes: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case coachUserId = "coach_user_id"
        case athleteId = "athlete_id"
        case stage
        case tags
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var pipelineStage: PipelineStage {
        PipelineStage(rawValue: stage) ?? .watching
    }
}
