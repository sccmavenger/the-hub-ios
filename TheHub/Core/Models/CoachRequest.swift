import Foundation

struct CoachRequest: Codable, Identifiable {
    let id: String
    let userId: String
    let fullName: String
    let email: String
    var title: String?
    var college: String?
    var message: String?
    let status: CoachRequestStatus
    var reviewedAt: String?
    var reviewedBy: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fullName = "full_name"
        case email
        case title
        case college
        case message
        case status
        case reviewedAt = "reviewed_at"
        case reviewedBy = "reviewed_by"
        case createdAt = "created_at"
    }
}
