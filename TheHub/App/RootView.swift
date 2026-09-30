import SwiftUI
import Auth

struct RootView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        Group {
            if authViewModel.isLoading {
                SplashView()
            } else if authViewModel.session != nil {
                MainTabView()
            } else {
                SignInView()
            }
        }
        // The design system is dark-only; without this, system-styled elements
        // (nav titles, lists, pickers, keyboard) follow the device's light mode
        // and render black text on our near-black backgrounds.
        .preferredColorScheme(.dark)
        .tint(Color.hubPrimary)
        .task {
            await authViewModel.initialize()
        }
        // Remote feature flags (e.g. the college-logo kill switch) need a
        // session to read, so load them once the user is signed in.
        .task(id: authViewModel.session?.user.id) {
            if authViewModel.session != nil {
                await AppSettingsService.shared.loadIfNeeded()
            } else {
                AppSettingsService.shared.reset()
            }
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            VStack(spacing: 24) {
                // Official logo — navy artwork on a white card, matching sign-in
                Image("HubLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 230)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                ProgressView()
                    .tint(Color.hubPrimary)
            }
        }
    }
}
