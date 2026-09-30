import SwiftUI
import Auth

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        Group {
            switch authViewModel.primaryRole {
            case .athlete, .parent:
                AthleteTabView()
            case .coach:
                WebToolsTabView()
            case .admin:
                AdminTabView()
            case nil:
                if authViewModel.roleLoadFailed {
                    RoleLoadErrorView()
                } else {
                    PendingApprovalView()
                }
            }
        }
    }
}

// MARK: - Athlete / Parent tabs

private struct AthleteTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(tabSelection: $selection)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            ProfileEditView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(1)

            CollegeListView()
                .tabItem { Label("Colleges", systemImage: "building.2") }
                .tag(2)

            MessagesTabView()
                .tabItem { Label("Messages", systemImage: "message") }
                .tag(3)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(4)
        }
        .tint(Color.hubPrimary)
    }
}

// MARK: - Coach / admin accounts

/// The iOS app is the athlete & family experience; coach and admin tools live
/// on the web. Coach/admin sign-ins get this signpost plus the shared More
/// screen (Account, sign out) instead of placeholder tabs.
private struct WebToolsTabView: View {
    var body: some View {
        TabView {
            ZStack {
                Color.hubBackground.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.hubPrimary)
                    Text("Your Tools Are on the Web")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("The Hub app is built for athletes and their families. Coach and admin tools — athlete search, pipeline, messaging, and approvals — are available on The Hub for web.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .tabItem { Label("Overview", systemImage: "house") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .tint(Color.hubPrimary)
    }
}

// MARK: - Admin tabs

/// Staff console. Full user/report/coach-approval management lives in the web
/// admin portal; this surfaces the controls that have to be reachable from a
/// phone — today the college-logo kill switch, which may need flipping fast.
private struct AdminTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                AdminSettingsView()
            }
            .tabItem { Label("Admin", systemImage: "slider.horizontal.3") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .tint(Color.hubPrimary)
    }
}

// MARK: - Role load failure

private struct RoleLoadErrorView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.hubWarning)
                Text("Couldn't Load Your Account")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    Task {
                        isRetrying = true
                        await authViewModel.refreshRoles()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView().tint(Color.hubPrimary)
                    } else {
                        Text("Try Again").bold()
                    }
                }
                .foregroundStyle(Color.hubPrimary)
                Button("Sign Out") {
                    Task { await authViewModel.signOut() }
                }
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
            }
        }
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
                    .foregroundStyle(Color.hubPrimary)
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
                .foregroundStyle(Color.hubPrimary)
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
                        // Both are tied to an athlete profile, so they'd only
                        // show empty states for a coach or staff account.
                        if authViewModel.currentRoles.contains(.athlete)
                            || authViewModel.currentRoles.contains(.parent) {
                            NavigationLink("Insights") {
                                InsightsRootView()
                            }
                            NavigationLink("NCAA Journey") {
                                NCAAJourneyRootView()
                            }
                        }
                        NavigationLink("Account") {
                            AccountView()
                        }
                        if authViewModel.currentRoles.contains(.admin) {
                            NavigationLink("Admin Settings") {
                                AdminSettingsView()
                            }
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

