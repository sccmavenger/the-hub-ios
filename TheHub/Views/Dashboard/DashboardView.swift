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
                        .tint(Color.hubGold)
                } else if let message = viewModel.errorMessage {
                    errorState(message)
                } else if let athlete = viewModel.athlete {
                    content(for: athlete)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await load() }
    }

    private func load() async {
        guard let userId = authViewModel.session?.user.id.uuidString else { return }
        await viewModel.load(userId: userId)
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
            .foregroundStyle(Color.hubGold)
        }
    }

    private func content(for athlete: Athlete) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header(for: athlete)
                completenessCard
                activityCards
                quickActions
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    // MARK: - Header

    private func header(for athlete: Athlete) -> some View {
        HStack(spacing: 14) {
            KFImage(URL(string: athlete.profilePhotoUrl ?? ""))
                .placeholder {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.hubTextSecondary)
                }
                .resizable()
                .scaledToFill()
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
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubSuccess)
            } else {
                Label("Draft", systemImage: "eye.slash")
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
                Text("Profile Strength")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(viewModel.completenessScore)%")
                    .font(.title2.bold())
                    .foregroundStyle(Color.hubGold)
            }

            ProgressView(value: Double(viewModel.completenessScore), total: 100)
                .tint(Color.hubGold)

            let missing = viewModel.scoreItems.filter { !$0.isComplete }
            if missing.isEmpty {
                Label("Your profile is complete — great work!", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubSuccess)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(missing.prefix(3)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.hubGold)
                            Text(item.label)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("+\(item.points)")
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Activity

    private var activityCards: some View {
        HStack(spacing: 12) {
            statCard(
                value: viewModel.profileViews90d,
                label: "Views (90d)",
                systemImage: "eye"
            )
            statCard(
                value: viewModel.coachSaves,
                label: "Coach Saves",
                systemImage: "bookmark"
            )
            statCard(
                value: viewModel.unreadMessages,
                label: "Unread",
                systemImage: "envelope.badge"
            )
        }
    }

    private func statCard(value: Int, label: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.hubGold)
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                quickActionButton("Edit Profile", systemImage: "pencil") {
                    tabSelection = 1
                }
                quickActionButton("My Colleges", systemImage: "building.2") {
                    tabSelection = 2
                }
            }
        }
    }

    private func quickActionButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(label)
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .foregroundStyle(Color.hubGold)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.hubBorder, lineWidth: 1)
        )
    }
}
