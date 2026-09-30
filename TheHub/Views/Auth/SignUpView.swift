import SwiftUI

struct SignUpView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRole: AppRole? = nil
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    // Athlete date of birth — required for COPPA age checks
    @State private var dateOfBirth = Date(timeIntervalSince1970: 1_262_304_000) // Jan 1, 2010 — starting point

    private var athleteAge: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now).year ?? 0
    }

    private var isUnder13: Bool { athleteAge < 13 }

    // College Coach application claims. Sent as signup metadata; the server
    // files a PENDING coach request and grants no role (supabase/014).
    @State private var coachTitle = ""
    @State private var institution = ""
    @State private var coachSportGender: SportGender? = nil
    @State private var governingBody: GoverningBody? = nil
    @State private var numberedDivision: String? = nil
    @State private var divisionText = ""
    @State private var athleticsUrl = ""
    @State private var programUrl = ""
    @State private var phone = ""
    @State private var verificationNote = ""

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEmailConfirmation = false
    @State private var legalDocument: LegalDocument?

    // Admin is never a sign-up option. Coach sign-up is an *application*:
    // the account works immediately, coach access waits for admin approval.
    private let signupRoles: [AppRole] = [.athlete, .parent, .coach]

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    rolePicker
                    if let role = selectedRole {
                        formFields(for: role)
                        if let error = errorMessage {
                            HubErrorText(message: error)
                        }
                        HubPrimaryButton(
                            "Create Account",
                            isLoading: isLoading,
                            isDisabled: !isFormValid(role: role)
                        ) {
                            Task { await signUp(role: role) }
                        }
                    }
                    Spacer(minLength: 24)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Confirm Your Email", isPresented: $showEmailConfirmation) {
            Button("OK") { dismiss() }
        } message: {
            if selectedRole == .coach {
                Text("We sent a confirmation link to \(email). Tap it, then sign in to track your coach application.")
            } else {
                Text("We sent a confirmation link to \(email). Tap it, then come back and sign in.")
            }
        }
        .sheet(item: $legalDocument) { document in
            LegalView(document: document)
        }
    }

    // MARK: - Subviews

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How will you use The Hub?")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                ForEach(signupRoles, id: \.self) { role in
                    RoleButton(role: role, isSelected: selectedRole == role) {
                        selectedRole = role
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formFields(for role: AppRole) -> some View {
        VStack(spacing: 16) {
            HubTextField(label: "Full Name", text: $fullName, textContentType: .name, autocapitalization: .words)
            HubTextField(label: "Email", text: $email, keyboardType: .emailAddress, textContentType: .emailAddress)
            if role == .coach {
                // A school domain is a verification *signal*, not a requirement —
                // athletics departments use many domains, so .edu is not enforced.
                Text("Use your official school or athletics email when possible. It helps us verify your affiliation faster.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HubSecureField(label: "Password", text: $password)
            // Reserve the hint's space instead of inserting/removing a view:
            // the layout shift on each keystroke was re-creating the
            // SecureField and dropping buffered input for fast typists.
            Text(passwordHint)
                .font(.caption)
                .foregroundStyle(Color.hubWarning)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
            HubSecureField(label: "Confirm Password", text: $confirmPassword)

            if role == .athlete {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Date of Birth")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.hubTextSecondary)

                    DatePicker(
                        "",
                        selection: $dateOfBirth,
                        in: Calendar.current.date(byAdding: .year, value: -100, to: .now)!...Date.now,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color.hubPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isUnder13 {
                    VStack(spacing: 10) {
                        Text("Athletes under 13 can't create their own account. A parent or guardian needs to create and manage the profile.")
                            .font(.caption)
                            .foregroundStyle(Color.hubWarning)
                            .multilineTextAlignment(.center)

                        Button("Sign up as a parent instead") {
                            selectedRole = .parent
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.hubPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.hubWarning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if role == .parent {
                Text("Parents create and manage their athlete's profile, or link to an existing one with an invite code.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .multilineTextAlignment(.center)
            }

            if role == .coach {
                coachFields
            }

            termsConsent
        }
    }

    /// Program affiliation claims. Everything here is reviewed by an admin
    /// before any athlete data becomes visible.
    private var coachFields: some View {
        VStack(spacing: 16) {
            Divider().background(Color.hubBorder)

            Text("Your Program")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            HubTextField(label: "Job Title", text: $coachTitle, textContentType: .jobTitle, autocapitalization: .words, maxLength: 120)
            HubTextField(label: "Institution / College", text: $institution, textContentType: .organizationName, autocapitalization: .words, maxLength: 200)

            HubSegmentedField(label: "Basketball Program", selection: $coachSportGender, options: SportGender.allCases) {
                $0.displayName
            }

            HubMenuField(
                label: "Association",
                selection: $governingBody,
                options: GoverningBody.allCases,
                placeholder: "Select…"
            ) { $0.displayName }

            if let governingBody, governingBody.hasNumberedDivisions {
                HubSegmentedField(label: "Division", selection: $numberedDivision, options: GoverningBody.numberedDivisions) {
                    $0.replacingOccurrences(of: "D", with: "Division ")
                }
            } else if let governingBody, governingBody != .naia {
                HubTextField(label: "Division / Level (optional)", text: $divisionText, autocapitalization: .words, maxLength: 40)
            }

            Text("Optional — speeds up verification")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            HubTextField(label: "Athletics Staff Directory URL", text: $athleticsUrl, keyboardType: .URL, textContentType: .URL)
            HubTextField(label: "Program Website URL", text: $programUrl, keyboardType: .URL, textContentType: .URL)
            HubTextField(label: "Phone", text: $phone, keyboardType: .phonePad, textContentType: .telephoneNumber, maxLength: 40)
            HubMultilineField(
                label: "Anything that helps us verify you",
                text: $verificationNote,
                placeholder: "e.g. where you're listed on the staff page",
                maxLength: 2000
            )

            Label(
                "Coach access is reviewed before it's granted. You can sign in right away to track your application; athlete recruiting features unlock once we verify your program affiliation.",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(Color.hubTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.hubSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var termsConsent: some View {
        VStack(spacing: 4) {
            Text("By creating an account, you agree to our")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
            HStack(spacing: 4) {
                Button("Terms of Service") { legalDocument = .terms }
                Text("and")
                    .foregroundStyle(Color.hubTextSecondary)
                Button("Privacy Policy") { legalDocument = .privacyPolicy }
            }
            .font(.caption.bold())
            .tint(Color.hubPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logic

    private var passwordHint: String {
        if !password.isEmpty && !password.isValidPassword {
            return "Password must be at least 8 characters."
        }
        if !confirmPassword.isEmpty && password != confirmPassword {
            return "Passwords don't match."
        }
        return " "
    }

    private func isFormValid(role: AppRole) -> Bool {
        guard !fullName.isBlank, email.isValidEmail,
              password.isValidPassword, password == confirmPassword else { return false }
        switch role {
        case .athlete:
            return !isUnder13
        case .coach:
            return coachApplication != nil
        case .parent, .admin:
            return true
        }
    }

    /// The claims to submit, or nil while required coach fields are missing.
    private var coachApplication: AuthService.CoachApplication? {
        guard !coachTitle.isBlank, !institution.isBlank,
              let coachSportGender, let governingBody else { return nil }
        let division: String?
        if governingBody.hasNumberedDivisions {
            // NCAA rules are division-specific; don't let an NCAA claim omit it.
            guard let numberedDivision else { return nil }
            division = numberedDivision
        } else if governingBody == .naia {
            division = nil
        } else {
            division = divisionText.isBlank ? nil : divisionText.trimmed
        }
        return AuthService.CoachApplication(
            fullName: fullName.trimmed,
            title: coachTitle.trimmed,
            institution: institution.trimmed,
            governingBody: governingBody,
            division: division,
            sportGender: coachSportGender,
            athleticsUrl: Self.normalizedURL(athleticsUrl),
            programUrl: Self.normalizedURL(programUrl),
            phone: phone.isBlank ? nil : phone.trimmed,
            note: verificationNote.isBlank ? nil : verificationNote.trimmed
        )
    }

    /// Coaches type "athletics.school.edu/staff"; the server only keeps
    /// http(s) URLs, so add the scheme rather than silently dropping the link.
    private static func normalizedURL(_ raw: String) -> String? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return value
        }
        return "https://" + value
    }

    private func signUp(role: AppRole) async {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let needsEmailConfirmation: Bool
            switch role {
            case .athlete:
                needsEmailConfirmation = try await AuthService.shared.signUpAthlete(
                    email: email,
                    password: password,
                    fullName: fullName.trimmed,
                    dateOfBirth: dateOfBirth.asDateOnlyString
                )
            case .parent:
                needsEmailConfirmation = try await AuthService.shared.signUpParent(
                    email: email, password: password, fullName: fullName.trimmed
                )
            case .coach:
                guard let coachApplication else {
                    errorMessage = "Please complete your program details."
                    return
                }
                needsEmailConfirmation = try await AuthService.shared.signUpCoach(
                    email: email, password: password, application: coachApplication
                )
            case .admin:
                return // never a sign-up option
            }

            if needsEmailConfirmation {
                showEmailConfirmation = true
            } else {
                // Auto-confirm environments sign straight in — refresh roles so
                // the tab view routes correctly without a relaunch
                await authViewModel.refreshRoles()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Role selector button

private struct RoleButton: View {
    let role: AppRole
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch role {
        case .athlete: "figure.basketball"
        case .parent: "person.2"
        case .coach: "clipboard"
        case .admin: "shield"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(role.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.hubPrimary.opacity(0.15) : Color.hubSurface)
            .foregroundStyle(isSelected ? Color.hubPrimary : Color.hubTextSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.hubPrimary : Color.hubBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
