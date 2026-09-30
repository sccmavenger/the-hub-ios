import SwiftUI
import Supabase

/// A coach's program-affiliation *claims* — what they type at sign-up or when
/// editing their application. Shared by SignUpView and
/// CoachApplicationEditView so both send the same shape to the server, where
/// `handle_new_user` / `update_coach_application` (supabase/014) sanitize it.
/// Nothing here is authoritative until an admin verifies it.
struct CoachProgramClaims: Equatable {
    var title = ""
    var institution = ""
    var sportGender: SportGender? = nil
    var governingBody: GoverningBody? = nil
    /// D1 / D2 / D3 for associations with numbered divisions (NCAA, NJCAA).
    var numberedDivision: String? = nil
    /// Free-text level for "Other" / "Not sure".
    var divisionText = ""
    var athleticsUrl = ""
    var programUrl = ""
    var phone = ""
    var note = ""

    init() {}

    init(from request: CoachRequest) {
        title = request.title ?? ""
        institution = request.college ?? ""
        sportGender = SportGender(rawValue: request.sportGender ?? "")
        governingBody = GoverningBody(rawValue: request.governingBody ?? "")
        if governingBody?.hasNumberedDivisions == true {
            numberedDivision = request.division
        } else {
            divisionText = request.division ?? ""
        }
        athleticsUrl = request.athleticsUrl ?? ""
        programUrl = request.programUrl ?? ""
        phone = request.phone ?? ""
        note = request.message ?? ""
    }

    /// The division claim that applies to the chosen association, or nil.
    var division: String? {
        guard let governingBody else { return nil }
        if governingBody.hasNumberedDivisions { return numberedDivision }
        if governingBody == .naia { return nil }   // single division in basketball
        return divisionText.isBlank ? nil : divisionText.trimmed
    }

    /// Required fields present. NCAA/NJCAA claims must name a division because
    /// the rules engine keys NCAA rules on it — never let it be guessed later.
    var isComplete: Bool {
        guard !title.isBlank, !institution.isBlank, sportGender != nil, let governingBody else { return false }
        return !governingBody.hasNumberedDivisions || numberedDivision != nil
    }

    /// Sign-up metadata, or nil while incomplete.
    func application(fullName: String) -> AuthService.CoachApplication? {
        guard isComplete, let sportGender, let governingBody else { return nil }
        return AuthService.CoachApplication(
            fullName: fullName,
            title: title.trimmed,
            institution: institution.trimmed,
            governingBody: governingBody,
            division: division,
            sportGender: sportGender,
            athleticsUrl: Self.normalizedURL(athleticsUrl),
            programUrl: Self.normalizedURL(programUrl),
            phone: phone.isBlank ? nil : phone.trimmed,
            note: note.isBlank ? nil : note.trimmed
        )
    }

    /// Payload for `update_coach_application`. Every editable key is present
    /// so a field the coach cleared is cleared server-side (explicit null),
    /// rather than silently kept.
    var rpcPayload: [String: AnyJSON] {
        func text(_ value: String) -> AnyJSON { value.isBlank ? .null : .string(value.trimmed) }
        return [
            "title": text(title),
            "college": text(institution),
            "governing_body": governingBody.map { .string($0.rawValue) } ?? .null,
            "division": division.map { .string($0) } ?? .null,
            "sport_gender": sportGender.map { .string($0.rawValue) } ?? .null,
            "athletics_url": Self.normalizedURL(athleticsUrl).map { .string($0) } ?? .null,
            "program_url": Self.normalizedURL(programUrl).map { .string($0) } ?? .null,
            "phone": text(phone),
            "message": text(note)
        ]
    }

    /// Coaches type "athletics.school.edu/staff"; the server only keeps
    /// http(s) URLs, so add the scheme rather than silently dropping the link.
    static func normalizedURL(_ raw: String) -> String? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return value }
        return "https://" + value
    }
}

/// The program-affiliation fields, in the app's form chrome.
struct CoachProgramClaimsFields: View {
    @Binding var claims: CoachProgramClaims

    var body: some View {
        VStack(spacing: 16) {
            HubTextField(label: "Job Title", text: $claims.title, textContentType: .jobTitle, autocapitalization: .words, maxLength: 120)
            HubTextField(label: "Institution / College", text: $claims.institution, textContentType: .organizationName, autocapitalization: .words, maxLength: 200)

            HubSegmentedField(label: "Basketball Program", selection: $claims.sportGender, options: SportGender.allCases) {
                $0.displayName
            }

            HubMenuField(
                label: "Association",
                selection: $claims.governingBody,
                options: GoverningBody.allCases,
                placeholder: "Select…"
            ) { $0.displayName }

            if let governingBody = claims.governingBody, governingBody.hasNumberedDivisions {
                HubSegmentedField(label: "Division", selection: $claims.numberedDivision, options: GoverningBody.numberedDivisions) {
                    $0.replacingOccurrences(of: "D", with: "Division ")
                }
            } else if let governingBody = claims.governingBody, governingBody != .naia {
                HubTextField(label: "Division / Level (optional)", text: $claims.divisionText, autocapitalization: .words, maxLength: 40)
            }

            Text("Optional — speeds up verification")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            HubTextField(label: "Athletics Staff Directory URL", text: $claims.athleticsUrl, keyboardType: .URL, textContentType: .URL)
            HubTextField(label: "Program Website URL", text: $claims.programUrl, keyboardType: .URL, textContentType: .URL)
            HubTextField(label: "Phone", text: $claims.phone, keyboardType: .phonePad, textContentType: .telephoneNumber, maxLength: 40)
            HubMultilineField(
                label: "Anything that helps us verify you",
                text: $claims.note,
                placeholder: "e.g. where you're listed on the staff page",
                maxLength: 2000
            )
        }
    }
}
