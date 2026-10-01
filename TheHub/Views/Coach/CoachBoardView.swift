import SwiftUI
import Auth
import Supabase

/// The program's shared Recruiting Board (spec §9.3, D11/W4/W5). Every
/// active verified staff member sees the same prospects and may change
/// stage, assign, remove or restore; each change is logged server-side.
struct CoachBoardView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared

    var initialStage: PipelineStage? = nil
    var initialMineOnly = false

    @State private var stage: PipelineStage?
    @State private var mineOnly = false
    @State private var includeRemoved = false
    @State private var items: [BoardListItem] = []
    @State private var stageCounts: [String: Int] = [:]
    @State private var assignedToMe = 0
    @State private var nextCursor: AnyJSON?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var isSeeded = false

    private var programId: String? { programs.selectedContext?.programId }
    private var userId: String? { authViewModel.session?.user.id.uuidString }

    private struct TaskKey: Hashable {
        let programId: String?
        let stage: PipelineStage?
        let mineOnly: Bool
        let includeRemoved: Bool
    }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            if programId == nil {
                CoachAccessUnavailableView()
            } else {
                content
            }
        }
        .navigationTitle("Recruiting Board")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { CoachProgramChip() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: $mineOnly) { Label("Assigned to me", systemImage: "person.crop.circle") }
                    Toggle(isOn: $includeRemoved) { Label("Show removed", systemImage: "archivebox") }
                } label: {
                    Image(systemName: mineOnly || includeRemoved ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Board options")
            }
        }
        .onAppear {
            guard !isSeeded else { return }
            stage = initialStage
            mineOnly = initialMineOnly
            isSeeded = true
        }
        .task(id: TaskKey(programId: programId, stage: stage, mineOnly: mineOnly, includeRemoved: includeRemoved)) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            StageChipBar(selection: $stage, counts: stageCounts)

            if isLoading && items.isEmpty {
                Spacer(); ProgressView().tint(Color.hubPrimary); Spacer()
            } else if let errorMessage, items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text(errorMessage).font(.subheadline).foregroundStyle(Color.hubTextSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                    Button("Try Again") { Task { await load() } }.font(.subheadline.bold()).foregroundStyle(Color.hubPrimary)
                }
                Spacer()
            } else if items.isEmpty {
                Spacer(); emptyState; Spacer()
            } else {
                List {
                    Section {
                        ForEach(items) { item in
                            NavigationLink {
                                CoachAthleteDetailView(athleteId: item.athlete.athleteId)
                            } label: {
                                AthleteCardView(
                                    athlete: item.athlete,
                                    boardStage: item.entry.stage,
                                    trailing: AnyView(trailing(for: item))
                                )
                                .opacity(item.entry.isRemoved ? 0.55 : 1)
                            }
                            .listRowBackground(Color.hubSurface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if item.entry.isRemoved {
                                    Button { Task { await restore(item) } } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                        .tint(Color.hubSuccess)
                                } else {
                                    Button(role: .destructive) { Task { await remove(item) } } label: { Label("Remove", systemImage: "trash") }
                                }
                            }
                            .contextMenu {
                                if !item.entry.isRemoved {
                                    Menu("Move to") {
                                        ForEach(PipelineStage.allCases, id: \.self) { s in
                                            Button(s.displayName) { Task { await setStage(item, s) } }
                                                .disabled(s == item.entry.stage)
                                        }
                                    }
                                    if let userId, item.entry.assignedTo == userId {
                                        Button("Unassign me") { Task { await assign(item, nil) } }
                                    } else {
                                        Button("Assign to me") { Task { await assign(item, userId) } }
                                    }
                                }
                            }
                            .onAppear {
                                if item.id == items.last?.id { Task { await loadMore() } }
                            }
                        }
                        if isLoadingMore {
                            HStack { Spacer(); ProgressView().tint(Color.hubPrimary); Spacer() }
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text(headerText).foregroundStyle(Color.hubTextSecondary)
                    } footer: {
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(Color.hubError)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
    }

    private func trailing(for item: BoardListItem) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let name = item.entry.assignedToName {
                Text(initials(name))
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.hubPrimary.opacity(0.6))
                    .clipShape(Circle())
                    .accessibilityLabel("Assigned to \(name)")
            }
            if item.hasPrivateNote {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .accessibilityLabel("You have a private note")
            }
        }
    }

    private var headerText: String {
        var parts: [String] = []
        parts.append(stage.map(\.displayName) ?? "All prospects")
        if mineOnly { parts.append("assigned to me") }
        if includeRemoved { parts.append("including removed") }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubTextSecondary)
            Text(stage == nil && !mineOnly
                 ? "No prospects yet. Find athletes in Discover and save them here."
                 : "Nothing here yet.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Data

    private func load() async {
        guard let programId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await CoachWorkspaceService.shared.boardList(
                programId: programId, stage: stage, assignedTo: mineOnly ? userId : nil, includeRemoved: includeRemoved
            )
            items = page.items
            stageCounts = page.stageCounts
            assignedToMe = page.assignedToMe
            nextCursor = page.nextCursor
        } catch {
            errorMessage = CoachDiscoverModel.message(for: error)
        }
    }

    private func loadMore() async {
        guard let programId, let cursor = nextCursor, cursor != .null, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await CoachWorkspaceService.shared.boardList(
                programId: programId, stage: stage, assignedTo: mineOnly ? userId : nil,
                includeRemoved: includeRemoved, cursor: cursor
            )
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            errorMessage = CoachDiscoverModel.message(for: error)
        }
    }

    private func apply(_ updated: BoardEntry, to item: BoardListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = BoardListItem(entry: updated, athlete: item.athlete, hasPrivateNote: item.hasPrivateNote)
    }

    private func setStage(_ item: BoardListItem, _ newStage: PipelineStage) async {
        do {
            let updated = try await CoachWorkspaceService.shared.setStage(entryId: item.entry.id, stage: newStage)
            apply(updated, to: item)
            await load()   // counts + filtered list
        } catch { errorMessage = "Couldn't change the stage." }
    }

    private func assign(_ item: BoardListItem, _ user: String?) async {
        do {
            let updated = try await CoachWorkspaceService.shared.assign(entryId: item.entry.id, to: user)
            apply(updated, to: item)
            if mineOnly { await load() }
        } catch { errorMessage = "Couldn't update the assignment." }
    }

    private func remove(_ item: BoardListItem) async {
        do {
            _ = try await CoachWorkspaceService.shared.removeFromBoard(entryId: item.entry.id)
            await load()
        } catch { errorMessage = "Couldn't remove this athlete." }
    }

    private func restore(_ item: BoardListItem) async {
        do {
            _ = try await CoachWorkspaceService.shared.restoreToBoard(entryId: item.entry.id)
            await load()
        } catch { errorMessage = "Couldn't restore this athlete. They may have unpublished their profile." }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return (first + last).uppercased()
    }
}
