import SwiftUI

struct SignUpView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRole: AppRole? = nil
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var college = ""
    @State private var title = ""
    @State private var coachMessage = ""

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCoachPending = false

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
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Application Submitted", isPresented: $showCoachPending) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your coach account is pending approval. You'll receive an email once reviewed.")
        }
    }

    // MARK: - Subviews

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("I am a...")
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
            HubSecureField(label: "Password", text: $password)
            HubSecureField(label: "Confirm Password", text: $confirmPassword)

            if role == .coach {
                Divider().background(Color.hubBorder)

                Text("Coach Information")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HubTextField(label: "College / University", text: $college)
                HubTextField(label: "Title (e.g. Assistant Coach)", text: $title)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Message (optional)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.hubTextSecondary)
                    TextEditor(text: $coachMessage)
                        .frame(minHeight: 80)
                        .padding(10)
                        .background(Color.hubSurface)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.hubBorder, lineWidth: 1)
                        )
                }

                Text("Coach accounts require admin approval before access is granted.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Logic

    private func isFormValid(role: AppRole) -> Bool {
        guard !fullName.isBlank, email.isValidEmail,
              password.isValidPassword, password == confirmPassword else { return false }
        if role == .coach {
            return !college.isBlank && !title.isBlank
        }
        return true
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
            switch role {
            case .athlete:
                try await AuthService.shared.signUpAthlete(
                    email: email, password: password, fullName: fullName.trimmed
                )
            case .parent:
                try await AuthService.shared.signUpParent(
                    email: email, password: password, fullName: fullName.trimmed
                )
            case .coach:
                try await AuthService.shared.signUpCoach(
                    email: email,
                    password: password,
                    fullName: fullName.trimmed,
                    college: college.trimmed,
                    title: title.trimmed,
                    message: coachMessage.isBlank ? nil : coachMessage.trimmed
                )
                showCoachPending = true
            case .admin:
                break
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
            .background(isSelected ? Color.hubGold.opacity(0.15) : Color.hubSurface)
            .foregroundStyle(isSelected ? Color.hubGold : Color.hubTextSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.hubGold : Color.hubBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
