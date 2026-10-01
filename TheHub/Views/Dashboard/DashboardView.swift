import SwiftUI
import Auth
import Kingfisher

struct DashboardView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Binding var tabSelection: Int
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.hubPrimary)
                } else if let message = viewModel.errorMessage, viewModel.athlete == nil {
                    errorState(message)
                } else if let athlete = viewModel.athlete {
                    content(for: athlete)
                } else {
                    noAthleteState
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.managedAthletes.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        athleteSwitcher
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let userId = authViewModel.session?.user.id.uuidString else {
            viewModel.isLoading = false
            return
        }
        await viewModel.load(userId: userId)
    }

    private var athleteSwitcher: some View {
        Menu {
            ForEach(viewModel.managedAthletes) { athlete in
                Button {
                    Task { await viewModel.select(athleteId: athlete.id) }
                } label: {
                    if athlete.id == viewModel.athlete?.id {
                        Label(athlete.fullName, systemImage: "checkmark")
                    } else {
                        Text(athlete.fullName)
                    }
                }
            }
        } label: {
            Image(systemName: "person.2.circle")
                .foregroundStyle(Color.hubPrimary)
        }
        .accessibilityLabel("Switch athlete")
    }

    // MARK: - Empty / error states

    private var noAthleteState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.basketball")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubPrimary)

            if authViewModel.primaryRole == .parent {
                Text("Create Your Athlete's Profile")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Set up and manage your athlete's recruiting profile from the Profile tab — you control what gets published.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Create Profile") {
                    tabSelection = 1
                }
                .foregroundStyle(Color.hubPrimary)
                .fontWeight(.semibold)
            } else {
                Text("Build Your Profile")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Create your athlete profile so college coaches can find you.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Create Profile") {
                    tabSelection = 1
                }
                .foregroundStyle(Color.hubPrimary)
                .fontWeight(.semibold)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubWarning)
            Text("Couldn't load your dashboard")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await load() }
            }
            .foregroundStyle(Color.hubPrimary)
        }
    }

    private func content(for athlete: Athlete) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header(for: athlete)
                profileButtons(for: athlete)
                completenessCard
                quickActions
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    private func profileButtons(for athlete: Athlete) -> some View {
        NavigationLink {
            PublicProfileView(athlete: athlete)
        } label: {
            HStack {
                Image(systemName: "eye")
                Text("View Profile")
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .foregroundStyle(.white)
        .background(Color.hubPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Header

    private func header(for athlete: Athlete) -> some View {
        HStack(spacing: 14) {
            HubRemoteImage(path: athlete.profilePhotoPath, legacyURL: athlete.profilePhotoUrl) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.hubTextSecondary)
            }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(athlete.fullName)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(athlete.gradYearDisplay)
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            }

            Spacer()

            if athlete.isPublished {
                Label("Visible to coaches", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubSuccess)
            } else {
                Label("Not published", systemImage: "eye.slash")
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubTextSecondary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Completeness

    private var completenessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile Strength")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(viewModel.completenessTone.label)
                        .font(.caption)
                        .foregroundStyle(viewModel.completenessTone.isPositive ? Color.hubSuccess : Color.hubWarning)
                }
                Spacer()
                Text("\(viewModel.completenessScore)%")
                    .font(.title2.bold())
                    .foregroundStyle(Color.hubPrimary)
            }

            ProgressView(value: Double(viewModel.completenessScore), total: 100)
                .tint(Color.hubPrimary)

            let missing = viewModel.completenessItems
                .filter { !$0.done }
                .sorted { $0.weight > $1.weight }
            if missing.isEmpty {
                Label("Your profile is complete — great work!", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubSuccess)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(missing.prefix(3)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.hubPrimary)
                            Text(item.label)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("+\(item.weight)")
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                        .font(.subheadline)
                    }
                }
                Button("Finish my profile") {
                    tabSelection = 1
                }
                .font(.subheadline.bold())
                .foregroundStyle(Color.hubPrimary)
            }
        }
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Quick actions

    @ViewBuilder
    private var quickActions: some View {
        if let athlete = viewModel.athlete,
           let userId = authViewModel.session?.user.id.uuidString {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Actions")
                    .font(.headline)
                    .foregroundStyle(.white)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    NavigationLink {
                        InsightsView(athlete: athlete)
                    } label: {
                        statCard(value: viewModel.profileViews, label: "Profile Views", systemImage: "eye")
                    }
                    NavigationLink {
                        BookmarksView(athlete: athlete)
                    } label: {
                        statCard(value: viewModel.coachSaves, label: "Bookmarks", systemImage: "bookmark")
                    }
                    NavigationLink {
                        ThreadsView(athlete: athlete, currentUserId: userId)
                    } label: {
                        statCard(value: viewModel.unreadMessages, label: "Unread", systemImage: "envelope.badge")
                    }
                    NavigationLink {
                        NCAAJourneyView(athlete: athlete)
                    } label: {
                        actionCard(title: "NCAA Journey", caption: "Eligibility roadmap", systemImage: "map")
                    }
                }
            }
        }
    }

    private func statCard(value: Int, label: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.hubPrimary)
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.vertical, 16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Navigation tile without a stat — same footprint as statCard so the grid stays even.
    private func actionCard(title: String, caption: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.hubPrimary)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.vertical, 16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

}
