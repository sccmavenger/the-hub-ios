import Foundation

struct Athlete: Codable, Identifiable {
    let id: String
    let userId: String
    var fullName: String
    var bio: String?
    var dateOfBirth: String?
    var profilePhotoUrl: String?
    var highSchool: String?
    var gradYear: Int?
    var gpa: Double?
    var satScore: Int?
    var actScore: Int?
    var heightInches: Int?
    var weightLbs: Int?
    var position: String?
    var jerseyNumber: String?
    var sportGender: String?
    var instagramHandle: String?
    var tiktokHandle: String?
    var intendedMajor: String?
    var hometown: String?
    var state: String?
    var zipCode: String?
    var latitude: Double?
    var longitude: Double?
    var ncaaId: String?
    var isPublished: Bool
    var guardianConsentAt: String?
    var guardianConsentEmail: String?
    var guardianConsentName: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fullName = "full_name"
        case bio
        case dateOfBirth = "date_of_birth"
        case profilePhotoUrl = "profile_photo_url"
        case highSchool = "high_school"
        case gradYear = "grad_year"
        case gpa
        case satScore = "sat_score"
        case actScore = "act_score"
        case heightInches = "height_inches"
        case weightLbs = "weight_lbs"
        case position
        case jerseyNumber = "jersey_number"
        case sportGender = "sport_gender"
        case instagramHandle = "instagram_handle"
        case tiktokHandle = "tiktok_handle"
        case intendedMajor = "intended_major"
        case hometown
        case state
        case zipCode = "zip_code"
        case latitude
        case longitude
        case ncaaId = "ncaa_id"
        case isPublished = "is_published"
        case guardianConsentAt = "guardian_consent_at"
        case guardianConsentEmail = "guardian_consent_email"
        case guardianConsentName = "guardian_consent_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var heightDisplay: String? {
        guard let inches = heightInches else { return nil }
        return "\(inches / 12)'\(inches % 12)\""
    }

    var gradYearDisplay: String {
        guard let year = gradYear else { return "Unknown" }
        return "Class of \(year)"
    }

    var completenessScore: Int {
        var score = 0
        if profilePhotoUrl != nil { score += 20 }
        if bio != nil && !(bio?.isEmpty ?? true) { score += 15 }
        if gpa != nil { score += 10 }
        if heightInches != nil && weightLbs != nil { score += 10 }
        return min(score, 100)
    }
}
