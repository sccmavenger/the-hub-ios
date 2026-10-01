import SwiftUI
import Auth

/// Coach Home (spec §10): the selected program, board counts by stage, what's
/// assigned to you, recent staff activity, and quick actions. All numbers come
/// from `coach_home_summary`, which honors blocks and removals.
struct CoachHomeView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared
    @Binding var tabSelection: CoachTab

    @State private var summary: CoachHomeSummary?
    @State private var summaryFailed = false
    @State private var showSwitcher = false

    private var userId: String? { authViewModel.session?.user.id.uuidString }
    private var programId: String? { programs.selectedContext?.programId }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    switch programs.load {
                    case .notLoaded, .loading:
                        ProgressView().tint(Color.hubPrimary).padding(.vertical, 24)
                    case .failed:
                        retryCard("Couldn't load your program.")
                    case .loaded(let contexts):
                        if let selected = programs.selectedContext {
                            programHeader(selected, count: contexts.count)
                            boardTiles
                            quickActions
                            if let summary, summary.unreadThreads > 0 {
                                messagesNote(summary.unreadThreads)
                            }
                            recentActivity
                        } else if contexts.isEmpty {
                            retryCard("Your verified program isn't available yet. Pull to refresh in a moment.")
                        } else {
                            ProgressView().tint(Color.hubPrimary).padding(.vertical, 24)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .refreshable {
                if let userId { await programs.refresh(coachUserId: userId) }
                await loadSummary()
            }
        }
        .navigationTitle("Coach Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { CoachProgramChip() }
        }
        .task(id: programId) { await loadSummary() }
        .sheet(isPresented: $showSwitcher) { CoachProgramSwitcherView() }
    }

    // MARK: - Sections

    private func programHeader(_ context: CoachProgramContext, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.hubSuccess)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.institutionName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text([context.programLabel, context.divisionLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                }
                Spacer()
            }
            if count > 1 {
                Button("Switch program") { showSwitcher = true }
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var boardTiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recruiting Board")
                    .font(.headline)
                    .foregroundStyle(Color.hubPrimary)
                Spacer()
                if let summary {
                    Text(summary.boardTotal == 1 ? "1 prospect" : "\(summary.boardTotal) prospects")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            if summaryFailed && summary == nil {
                Text("Couldn't load board counts. Pull to refresh.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            } else if let summary, summary.boardTotal == 0 {
                Text("No prospects yet. Find athletes in Discover and save them to your program's board.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(PipelineStage.allCases, id: \.self) { stage in
                        NavigationLink {
                            CoachBoardView(initialStage: stage)
                        } label: {
                            tile(title: stage.displayName, value: summary?.count(for: stage) ?? 0, tint: stage.color)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink {
                        CoachBoardView(initialMineOnly: true)
                    } label: {
                        tile(title: "Assigned to me", value: summary?.assignedToMe ?? 0, tint: Color.hubPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func tile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.hubSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button { tabSelection = .discover } label: {
                Label("Find athletes", systemImage: "magnifyingglass")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .background(Color.hubPrimary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button { tabSelection = .board } label: {
                Label("Open board", systemImage: "rectangle.stack")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .background(Color.hubSurface)
            .foregroundStyle(Color.hubPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func messagesNote(_ unread: Int) -> some View {
        Button {
            tabSelection = .messages
        } label: {
            Label {
                Text(unread == 1 ? "1 unread conversation" : "\(unread) unread conversations")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            } icon: {
                Image(systemName: "message.badge.fill").foregroundStyle(Color.hubPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.hubSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)
            if let summary, !summary.recentActivity.isEmpty {
                ForEach(summary.recentActivity) { row in
                    HStack(alignment: .top) {
                        Text(row.summary)
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(row.createdAt.asFormattedDate())
                            .font(.caption2)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                    .padding(.vertical, 1)
                }
            } else {
                Text("Board changes by you and your staff show up here.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
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

    // MARK: - Data

    private func loadSummary() async {
        guard let programId else { summary = nil; return }
        do {
            summary = try await CoachWorkspaceService.shared.homeSummary(programId: programId)
            summaryFailed = false
        } catch {
            summaryFailed = true
        }
    }
}

/// Verified program card shared by the Program tab and the switcher.
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
