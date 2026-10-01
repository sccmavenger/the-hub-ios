import SwiftUI
import Auth

/// Coach Mode Home (Phase 2B shape): the selected verified program, a switcher
/// when the coach holds several, and the account entry. 2D adds the board
/// counts, assigned-to-me tile and recent activity from `coach_home_summary`.
struct CoachHomeView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared
    @State private var showSwitcher = false

    private var userId: String? {
        authViewModel.session?.user.id.uuidString
    }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    switch programs.load {
                    case .notLoaded, .loading:
                        ProgressView().tint(Color.hubPrimary).padding(.vertical, 24)
                    case .failed:
                        retryCard("Couldn't load your program.")
                    case .loaded(let contexts):
                        if let selected = programs.selectedContext {
                            ProgramCardView(context: selected, isCurrent: true)
                            if programs.canSwitch {
                                Button {
                                    showSwitcher = true
                                } label: {
                                    Label("Switch program (\(contexts.count) verified)", systemImage: "arrow.left.arrow.right")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                }
                                .background(Color.hubSurface)
                                .foregroundStyle(Color.hubPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        } else if contexts.isEmpty {
                            retryCard("Your verified program isn't available yet. Pull to refresh in a moment.")
                        } else {
                            // Several programs, none chosen: the tab view presents the switcher.
                            ProgressView().tint(Color.hubPrimary).padding(.vertical, 24)
                        }
                    }
                    rulesCard
                    accountCard
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .refreshable {
                if let userId { await programs.refresh(coachUserId: userId) }
            }
        }
        .navigationTitle("Coach Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { CoachProgramChip() }
        }
        .sheet(isPresented: $showSwitcher) {
            CoachProgramSwitcherView()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.hubSuccess)
            VStack(alignment: .leading, spacing: 2) {
                Text("Program verified")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Coach Mode is active for your program.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var rulesCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recruiting rules")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Messages you send to athletes are evaluated against published recruiting rules for your verified program and the athlete's class. When a rule prohibits contact, The Hub tells you the date it opens.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        } icon: {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(Color.hubPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            NavigationLink {
                AccountView()
            } label: {
                HStack {
                    Label("Account & Legal", systemImage: "person.crop.circle")
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            Text("Changing schools? Contact \(HubSupport.email) and we'll move your verified membership.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func retryCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { if let userId { await programs.refresh(coachUserId: userId) } }
            }
            .font(.subheadline.bold())
            .foregroundStyle(Color.hubPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Verified program card shared by Home, the Program tab and the switcher.
struct ProgramCardView: View {
    let context: CoachProgramContext
    var isCurrent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isCurrent ? "Your program" : "Also verified")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.hubTextSecondary)
                Spacer()
                Text("Verified")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.hubSuccess)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.hubSuccess.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(context.institutionName)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(context.programLabel)
                .foregroundStyle(.white)
            if let division = context.divisionLabel {
                Text(division)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            let role = [context.title, context.roleDisplayName].compactMap { $0 }.joined(separator: " · ")
            if !role.isEmpty {
                Text(role)
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
                    .padding(.top, 2)
            }
            if let verified = context.verifiedAt {
                Text("Verified \(verified.asFormattedDate(style: .long))")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
