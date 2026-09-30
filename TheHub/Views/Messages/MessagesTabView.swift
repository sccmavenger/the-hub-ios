import SwiftUI
import Auth

/// Messages tab root — loads the signed-in user's athlete and hosts the
/// thread inbox (same screen the dashboard's Unread tile drills into).
struct MessagesTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var athlete: Athlete?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(Color.hubPrimary)
                } else if let athlete, let userId = authViewModel.session?.user.id.uuidString {
                    ThreadsView(athlete: athlete, currentUserId: userId)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        guard let userId = authViewModel.session?.user.id.uuidString else { return }
        do {
            athlete = try await AthleteService.shared.fetchManagedAthletes(userId: userId).first
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: loadFailed ? "exclamationmark.triangle" : "message")
                .font(.system(size: 40))
                .foregroundStyle(loadFailed ? Color.hubWarning : Color.hubTextSecondary)
            Text(loadFailed ? "Couldn't load messages" : "No profile yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text(loadFailed
                 ? "Check your connection and try again."
                 : "Messages are tied to an athlete profile. Create one from the Profile tab.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if loadFailed {
                Button("Try Again") {
                    Task {
                        isLoading = true
                        await load()
                    }
                }
                .foregroundStyle(Color.hubPrimary)
            }
        }
    }
}
