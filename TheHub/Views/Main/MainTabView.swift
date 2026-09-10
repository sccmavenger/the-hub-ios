import SwiftUI

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        Group {
            switch authViewModel.primaryRole {
            case .athlete, .parent:
                AthleteTabView()
            case .coach:
                CoachTabView()
            case .admin:
                AdminTabView()
            case nil:
                PendingApprovalView()
            }
        }
    }
}

// MARK: - Athlete / Parent tabs

private struct AthleteTabView: View {
    var body: some View {
        TabView {
            Text("Dashboard — coming soon")
                .tabItem { Label("Home", systemImage: "house") }

            Text("Profile Editor — coming soon")
                .tabItem { Label("Profile", systemImage: "person") }

            Text("Colleges — coming soon")
                .tabItem { Label("Colleges", systemImage: "building.2") }

            Text("Messages — coming soon")
                .tabItem { Label("Messages", systemImage: "message") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .tint(Color.hubGold)
    }
}

// MARK: - Coach tabs

private struct CoachTabView: View {
    var body: some View {
        TabView {
            Text("Athlete Directory — coming soon")
                .tabItem { Label("Athletes", systemImage: "person.3") }

            Text("Games Near Me — coming soon")
                .tabItem { Label("Games", systemImage: "calendar") }

            Text("Pipeline — coming soon")
                .tabItem { Label("Pipeline", systemImage: "chart.bar") }

            Text("Messages — coming soon")
                .tabItem { Label("Messages", systemImage: "message") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .tint(Color.hubGold)
    }
}

// MARK: - Admin tabs

private struct AdminTabView: View {
    var body: some View {
        TabView {
            Text("Admin Dashboard — coming soon")
                .tabItem { Label("Dashboard", systemImage: "gauge") }

            Text("Users — coming soon")
                .tabItem { Label("Users", systemImage: "person.2") }

            Text("Coach Requests — coming soon")
                .tabItem { Label("Requests", systemImage: "checkmark.circle") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .tint(Color.hubGold)
    }
}

// MARK: - Coach pending approval

private struct PendingApprovalView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "clock.badge")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.hubGold)
                Text("Account Pending Approval")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Your coach account is under review. You'll receive an email once approved.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Sign Out") {
                    Task { await authViewModel.signOut() }
                }
                .foregroundStyle(Color.hubGold)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - More sheet (shared)

struct MoreView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()
                List {
                    Section {
                        NavigationLink("Insights") {
                            Text("Insights — coming soon")
                        }
                        NavigationLink("Account") {
                            AccountPlaceholderView()
                        }
                    }
                    .listRowBackground(Color.hubSurface)

                    Section {
                        Button(role: .destructive) {
                            Task { await authViewModel.signOut() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    .listRowBackground(Color.hubSurface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct AccountPlaceholderView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Text(authViewModel.session?.user.email ?? "")
                    .foregroundStyle(Color.hubTextSecondary)
                Text("Account settings — coming soon")
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Account")
    }
}
