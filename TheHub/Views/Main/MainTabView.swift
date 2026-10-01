import SwiftUI
import Auth

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        Group {
            switch authViewModel.accountRoute {
            case .loading:
                AccountLoadingView()
            case .athlete, .parent:
                AthleteTabView()
            case .coach:
                CoachTabView()
            case .admin:
                AdminTabView()
            case .coachPending(let request),
                 .coachNeedsInformation(let request),
                 .coachRejected(let request),
                 .coachWithdrawn(let request),
                 .coachAccessPaused(let request):
                CoachApplicantTabView(request: request)
            case .roleLoadError:
                RoleLoadErrorView()
            case .accountConfigurationError:
                AccountConfigurationErrorView()
            }
        }
    }
}

// MARK: - Loading

private struct AccountLoadingView: View {
    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            ProgressView()
                .tint(Color.hubPrimary)
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

// MARK: - Coach Mode (approved coach)

/// Coach Mode 2.0 tabs. Messages joins in 2.1 (W1/W2); no placeholder tabs.
enum CoachTab: Hashable {
    case home, discover, board, program
}

/// Coach Workspace shell: Home · Discover · Board · Program, all scoped to the
/// selected verified program. Account/legal/sign-out live on the Program tab.
private struct CoachTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared
    @State private var selection: CoachTab = .home

    private var userId: String? {
        authViewModel.session?.user.id.uuidString
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                CoachHomeView(tabSelection: $selection)
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(CoachTab.home)

            NavigationStack {
                CoachDiscoverView()
            }
            .tabItem { Label("Discover", systemImage: "magnifyingglass") }
            .tag(CoachTab.discover)

            NavigationStack {
                CoachBoardView()
            }
            .tabItem { Label("Board", systemImage: "rectangle.stack") }
            .tag(CoachTab.board)

            NavigationStack {
                CoachProgramView()
            }
            .tabItem { Label("Program", systemImage: "building.columns") }
            .tag(CoachTab.program)
        }
        .tint(Color.hubPrimary)
        // Program contexts load once here; every coach screen reads
        // `CoachProgramService.shared.selectedContext`.
        .task(id: userId) {
            guard let userId else { return }
            await programs.refresh(coachUserId: userId)
        }
        // A multi-program coach with no valid stored choice must pick before
        // any program-scoped screen loads (D16): modal, not dismissable.
        .sheet(isPresented: Binding(
            get: { programs.needsProgramChoice },
            set: { _ in }
        )) {
            CoachProgramSwitcherView(isDismissable: false)
        }
    }
}

// MARK: - Admin tabs

/// Staff console: coach application review (approve / reject / request info,
/// membership suspension) and the remote feature switches. User and report
/// management still live in the web admin portal.
private struct AdminTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                CoachApplicationsView()
            }
            .tabItem { Label("Coaches", systemImage: "checkmark.shield") }

            NavigationStack {
                AdminSettingsView()
            }
            .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }

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

// MARK: - Coach applicant (pending / needs info / rejected / withdrawn / paused)

/// A coach whose application isn't (or is no longer) approved. Full account
/// access — status, edit/resubmit, Account, legal, sign out — and zero athlete
/// content: the account holds no coach role, and RLS enforces that regardless.
private struct CoachApplicantTabView: View {
    let request: CoachRequest

    var body: some View {
        TabView {
            NavigationStack {
                CoachApplicationStatusView(request: request)
            }
            .tabItem { Label("Application", systemImage: "checkmark.shield") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .tint(Color.hubPrimary)
    }
}

// MARK: - No role, no application

/// Signed in, but the account has no role and never filed a coach
/// application — the sign-up trigger didn't run or the account was altered.
/// Not a coach-pending state; don't dress it up as one.
private struct AccountConfigurationErrorView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.hubWarning)
                Text("Your Account Needs Setup")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("We couldn't find a role or a coach application for this account. Contact support and we'll sort it out.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if let url = URL(string: "mailto:\(HubSupport.email)?subject=Account%20setup") {
                    Link("Contact Support", destination: url)
                        .bold()
                        .foregroundStyle(Color.hubPrimary)
                }
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
                        Text("Check Again")
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
                            NavigationLink("Coach Applications") {
                                CoachApplicationsView()
                            }
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

