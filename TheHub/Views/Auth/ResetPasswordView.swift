import SwiftUI

struct ResetPasswordView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isLoading = false
    @State private var didSend = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "lock.rotation")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.hubGold)

                    VStack(spacing: 8) {
                        Text("Reset Password")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("Enter your email and we'll send you a reset link.")
                            .font(.subheadline)
                            .foregroundStyle(Color.hubTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if didSend {
                        sentConfirmation
                    } else {
                        emailForm
                    }

                    Spacer()
                    Spacer()
                }
            }
            .navigationTitle("Forgot Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.hubGold)
                }
            }
        }
    }

    private var sentConfirmation: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(Color.hubSuccess)
            Text("Reset email sent!")
                .foregroundStyle(.white)
                .fontWeight(.medium)
            Text("Check your inbox and follow the link to reset your password.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private var emailForm: some View {
        VStack(spacing: 16) {
            HubTextField(
                label: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress
            )

            if let error = authViewModel.errorMessage {
                HubErrorText(message: error)
            }

            HubPrimaryButton(
                "Send Reset Link",
                isLoading: isLoading,
                isDisabled: !email.isValidEmail
            ) {
                Task { await sendReset() }
            }
        }
        .padding(.horizontal, 24)
    }

    private func sendReset() async {
        isLoading = true
        let success = await authViewModel.resetPassword(email: email)
        isLoading = false
        if success { didSend = true }
    }
}
