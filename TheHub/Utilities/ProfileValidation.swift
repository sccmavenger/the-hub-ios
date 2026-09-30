import Foundation

/// Field validation rules — ported from the web app's zod schemas (validation.ts).
enum ProfileValidation {
    static func validateAthlete(
        fullName: String,
        state: String,
        zipCode: String,
        gradYear: Int?,
        heightInches: Int?,
        weightLbs: Int?,
        gpa: Double?,
        satScore: Int?,
        actScore: Int?,
        bio: String
    ) -> [String] {
        var errors: [String] = []
        let name = fullName.trimmingCharacters(in: .whitespaces)
        if name.count < 2 || name.count > 100 {
            errors.append("Name must be 2–100 characters.")
        }
        let trimmedState = state.trimmingCharacters(in: .whitespaces)
        if !trimmedState.isEmpty, !(trimmedState.count == 2 && trimmedState.allSatisfy(\.isLetter)) {
            errors.append("State must be a 2-letter code (e.g. KS).")
        }
        let trimmedZip = zipCode.trimmingCharacters(in: .whitespaces)
        if !trimmedZip.isEmpty, !(trimmedZip.count == 5 && trimmedZip.allSatisfy(\.isNumber)) {
            errors.append("ZIP code must be 5 digits.")
        }
        if let gradYear {
            let year = Calendar.current.component(.year, from: .now)
            if gradYear < year - 1 || gradYear > year + 8 {
                errors.append("Graduation year must be between \(year - 1) and \(year + 8).")
            }
        }
        if let heightInches, !(40...96).contains(heightInches) {
            errors.append("Height must be between 40 and 96 inches.")
        }
        if let weightLbs, !(60...400).contains(weightLbs) {
            errors.append("Weight must be between 60 and 400 lbs.")
        }
        if let gpa, !(0...5).contains(gpa) {
            errors.append("GPA must be between 0 and 5.")
        }
        if let satScore, !(400...1600).contains(satScore) {
            errors.append("SAT score must be between 400 and 1600.")
        }
        if let actScore, !(1...36).contains(actScore) {
            errors.append("ACT score must be between 1 and 36.")
        }
        if bio.count > 1000 {
            errors.append("Bio must be 1000 characters or fewer.")
        }
        return errors
    }

    static func validateContact(
        athleteEmail: String,
        athletePhone: String,
        guardianEmail: String,
        guardianPhone: String,
        clubCoachPhone: String
    ) -> [String] {
        var errors: [String] = []
        for (label, email) in [("Athlete", athleteEmail), ("Guardian", guardianEmail)] {
            let trimmed = email.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.isValidEmail {
                errors.append("\(label) email doesn't look valid.")
            }
        }
        for (label, phone) in [("Athlete", athletePhone), ("Guardian", guardianPhone), ("Club coach", clubCoachPhone)] {
            let trimmed = phone.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !isValidPhone(trimmed) {
                errors.append("\(label) phone doesn't look valid.")
            }
        }
        return errors
    }

    /// Web regex: ^[0-9()+\-.\s]{7,20}$
    static func isValidPhone(_ phone: String) -> Bool {
        guard (7...20).contains(phone.count) else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789()+-. ")
        return phone.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
