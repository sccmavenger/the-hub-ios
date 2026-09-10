import SwiftUI

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
        .task {
            await authViewModel.initialize()
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "basketball")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.hubGold)
                Text("The Hub")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("by Summit Hoops")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
                ProgressView()
                    .tint(Color.hubGold)
                    .padding(.top, 8)
            }
        }
    }
}
