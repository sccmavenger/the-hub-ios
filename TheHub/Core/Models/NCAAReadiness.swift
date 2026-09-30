import Foundation

/// Self-reported NCAA eligibility progress for an athlete.
/// `source` records provenance — everything starts self-reported; higher
/// verification levels arrive with future school/NCAA integrations.
struct NCAAReadiness: Codable, Equatable {
    enum Division: String, Codable, CaseIterable {
        case d1 = "D1"
        case d2 = "D2"
        case d3 = "D3"
        case unsure = "Unsure"
    }

    enum AccountStatus: String, Codable {
        case notStarted = "not_started"
        case profilePage = "profile_page"
        case certification = "certification"
    }

    var athleteId: String
    var intendedDivision: Division
    var ecAccountStatus: AccountStatus
    var coreCoursesCompleted: Int
    var estimatedCoreGpa: Double?
    var transcriptSent: Bool
    var amateurismDone: Bool
    var finalCertRequested: Bool
    var source: String
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case athleteId = "athlete_id"
        case intendedDivision = "intended_division"
        case ecAccountStatus = "ec_account_status"
        case coreCoursesCompleted = "core_courses_completed"
        case estimatedCoreGpa = "estimated_core_gpa"
        case transcriptSent = "transcript_sent"
        case amateurismDone = "amateurism_done"
        case finalCertRequested = "final_cert_requested"
        case source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func empty(athleteId: String) -> NCAAReadiness {
        NCAAReadiness(
            athleteId: athleteId,
            intendedDivision: .unsure,
            ecAccountStatus: .notStarted,
            coreCoursesCompleted: 0,
            estimatedCoreGpa: nil,
            transcriptSent: false,
            amateurismDone: false,
            finalCertRequested: false,
            source: "self_reported",
            createdAt: nil,
            updatedAt: nil
        )
    }
}
