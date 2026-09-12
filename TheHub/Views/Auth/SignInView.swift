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

                        // Logo — navy artwork, so it sits on a white card over the dark theme
                        Image("HubLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 230)
                            .padding(.vertical, 20)
                            .padding(.horizontal, 16)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20))

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
