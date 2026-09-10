import SwiftUI

struct SignInView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showSignUp = false
    @State private var showResetPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        Spacer().frame(height: 40)

                        // Logo
                        VStack(spacing: 8) {
                            Image(systemName: "basketball")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.hubGold)
                            Text("The Hub")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Text("by Summit Hoops")
                                .font(.subheadline)
                                .foregroundStyle(Color.hubTextSecondary)
                        }

                        VStack(spacing: 16) {
                            HubTextField(
                                label: "Email",
                                text: $email,
                                keyboardType: .emailAddress,
                                textContentType: .emailAddress
                            )
                            HubSecureField(label: "Password", text: $password)
                        }
                        .padding(.horizontal, 24)

                        if let error = authViewModel.errorMessage {
                            HubErrorText(message: error)
                                .padding(.horizontal, 24)
                        }

                        HubPrimaryButton(
                            "Sign In",
                            isLoading: isLoading,
                            isDisabled: email.isBlank || password.isBlank
                        ) {
                            Task { await signIn() }
                        }
                        .padding(.horizontal, 24)

                        Button("Forgot password?") {
                            showResetPassword = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.hubGold)

                        Spacer(minLength: 24)

                        Button {
                            showSignUp = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Don't have an account?")
                                    .foregroundStyle(Color.hubTextSecondary)
                                Text("Sign Up")
                                    .foregroundStyle(Color.hubGold)
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }

                        Spacer().frame(height: 24)
                    }
                }
            }
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
            .sheet(isPresented: $showResetPassword) {
                ResetPasswordView()
            }
        }
    }

    private func signIn() async {
        isLoading = true
        await authViewModel.signIn(email: email, password: password)
        isLoading = false
    }
}
