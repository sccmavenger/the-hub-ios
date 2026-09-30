import Foundation

/// A normalized college basketball program (`recruiting_programs`, 010/014).
/// Men's and women's programs at the same school are separate rows. A program
/// is *verified* once an admin confirms institution, association, division,
/// sport and gender — until then it must not drive any authorization.
nonisolated struct RecruitingProgram: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var institutionName: String
    var normalizedInstitutionName: String
    var governingBody: String
    var division: String?
    var sport: String
    var sportGender: String
    var athleticsUrl: String?
    var programUrl: String?
    var officialUrl: String?
    var active: Bool
    var verifiedAt: String?
    var verifiedBy: String?
    let createdAt: String
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case institutionName = "institution_name"
        case normalizedInstitutionName = "normalized_institution_name"
        case governingBody = "governing_body"
        case division
        case sport
        case sportGender = "sport_gender"
        case athleticsUrl = "athletics_url"
        case programUrl = "program_url"
        case officialUrl = "official_url"
        case active
        case verifiedAt = "verified_at"
        case verifiedBy = "verified_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isVerified: Bool { verifiedAt != nil }

    /// "Men's Basketball"
    var programLabel: String {
        let gender = SportGender(rawValue: sportGender)?.displayName
        return [gender, sport.capitalized].compactMap { $0 }.joined(separator: " ")
    }

    /// "Test University Men's Basketball" — same shape as coach_program_label().
    var fullLabel: String {
        "\(institutionName) \(programLabel)"
    }

    /// "NCAA Division I"
    var divisionLabel: String? {
        GoverningBody.divisionLabel(governingBody: governingBody, division: division)
    }
}
