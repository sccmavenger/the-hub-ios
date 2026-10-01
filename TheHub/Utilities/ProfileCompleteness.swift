import Foundation

/// Profile completeness scoring — exact port of the web app's completeness.ts.
/// 14 items with weights summing to 110; score = round(earned / 110 * 100).
enum ProfileCompleteness {
    struct Item: Identifiable {
        let key: String
        let label: String
        let weight: Int
        let done: Bool

        var id: String { key }
    }

    struct Tone {
        let label: String
        let isPositive: Bool
    }

    static func items(
        athlete: Athlete,
        videoCount: Int,
        photoCount: Int,
        eventCount: Int,
        hasContact: Bool
    ) -> [Item] {
        [
            Item(key: "name", label: "Name", weight: 5, done: !athlete.fullName.isBlank),
            Item(key: "photo", label: "Profile photo", weight: 10, done: athlete.hasProfilePhoto),
            Item(key: "school", label: "High school", weight: 5, done: !(athlete.highSchool ?? "").isBlank),
            Item(key: "grad", label: "Grad year", weight: 10, done: athlete.gradYear != nil),
            Item(key: "position", label: "Position", weight: 10, done: !(athlete.position ?? "").isBlank),
            Item(key: "measurements", label: "Height & weight", weight: 10,
                 done: athlete.heightInches != nil && athlete.weightLbs != nil),
            Item(key: "gpa", label: "GPA", weight: 10, done: athlete.gpa != nil),
            Item(key: "zip", label: "ZIP code", weight: 10, done: !(athlete.zipCode ?? "").isBlank),
            Item(key: "video", label: "Highlight video", weight: 15, done: videoCount > 0),
            Item(key: "photos", label: "Action photos", weight: 3, done: photoCount > 0),
            Item(key: "events", label: "Upcoming games", weight: 7, done: eventCount > 0),
            Item(key: "bio", label: "Bio", weight: 3, done: !(athlete.bio ?? "").isBlank),
            Item(key: "contact", label: "Contact info", weight: 5, done: hasContact),
            Item(key: "published", label: "Profile published", weight: 7, done: athlete.isPublished)
        ]
    }

    static func score(items: [Item]) -> Int {
        let total = items.map(\.weight).reduce(0, +)
        guard total > 0 else { return 0 }
        let earned = items.filter(\.done).map(\.weight).reduce(0, +)
        return Int((Double(earned) / Double(total) * 100).rounded())
    }

    static func tone(score: Int) -> Tone {
        switch score {
        case 90...: Tone(label: "Recruit-ready", isPositive: true)
        case 65...: Tone(label: "Almost there", isPositive: true)
        case 35...: Tone(label: "Needs work", isPositive: false)
        default: Tone(label: "Just getting started", isPositive: false)
        }
    }
}
