import SwiftUI
import Supabase

/// Discover (spec §8.2, D12/D19): server-side search of published athletes
/// in the selected program's sport and gender. The client sends filters and a
/// cursor; the server applies authorization, blocks, gender, the safe-field
/// allowlist and paging. Nothing is filtered locally.
@MainActor
@Observable
final class CoachDiscoverModel {
    var filters = DiscoverFilters()
    var queryText = ""
    private(set) var items: [CoachAthleteCard] = []
    private(set) var total = 0
    private(set) var nextCursor: AnyJSON?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var loadedForProgram: String?

    var hasMore: Bool {
        if let nextCursor, nextCursor != .null { return true }
        return false
    }

    var effectiveFilters: DiscoverFilters {
        var f = filters
        f.query = queryText.isBlank ? nil : queryText.trimmed
        return f
    }

    func run(programId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await CoachWorkspaceService.shared.search(programId: programId, filters: effectiveFilters)
            items = page.items
            total = page.total
            nextCursor = page.nextCursor
            loadedForProgram = programId
        } catch {
            items = []
            total = 0
            nextCursor = nil
            errorMessage = Self.message(for: error)
        }
    }

    func loadMore(programId: String) async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await CoachWorkspaceService.shared.search(programId: programId, filters: effectiveFilters, cursor: cursor)
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func apply(_ saved: CoachSavedSearch) {
        filters = saved.filters
        queryText = saved.filters.query ?? ""
    }

    static func message(for error: any Error) -> String {
        if let pg = error as? PostgrestError, pg.message == "not authorized" {
            return "Your program access changed. Pull to refresh or choose a program."
        }
        return "Couldn't load athletes. Check your connection and try again."
    }
}

struct CoachDiscoverView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared
    @State private var model = CoachDiscoverModel()
    @State private var showFilters = false
    @State private var showSavedSearches = false
    @State private var showSaveSearch = false

    private var programId: String? { programs.selectedContext?.programId }
    private var userId: String? { authViewModel.session?.user.id.uuidString }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if programId == nil {
                CoachAccessUnavailableView()
            } else {
                content
            }
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.queryText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name")
        .onSubmit(of: .search) { Task { await runIfPossible() } }
        .onChange(of: model.queryText) { _, newValue in
            if newValue.isEmpty { Task { await runIfPossible() } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { CoachProgramChip() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showSavedSearches = true
                } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel("Saved searches")
                Button {
                    showFilters = true
                } label: {
                    Image(systemName: model.filters.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filters, \(model.filters.activeCount) active")
            }
        }
        .task(id: TaskKey(programId: programId, filters: model.filters)) {
            await runIfPossible()
        }
        .sheet(isPresented: $showFilters) {
            DiscoverFiltersSheet(filters: model.filters) { model.filters = $0 }
        }
        .sheet(isPresented: $showSavedSearches) {
            if let programId, let userId {
                SavedSearchesView(programId: programId, coachUserId: userId, current: model.effectiveFilters) { saved in
                    model.apply(saved)
                }
            }
        }
    }

    private struct TaskKey: Hashable {
        let programId: String?
        let filters: DiscoverFilters
    }

    private func runIfPossible() async {
        guard let programId else { return }
        await model.run(programId: programId)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if model.filters.activeCount > 0 {
                activeFilterBar
            }

            if model.isLoading && model.items.isEmpty {
                Spacer()
                ProgressView().tint(Color.hubPrimary)
                Spacer()
            } else if let error = model.errorMessage, model.items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Try Again") { Task { await runIfPossible() } }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.hubPrimary)
                }
                Spacer()
            } else if model.items.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                List {
                    Section {
                        ForEach(model.items) { card in
                            NavigationLink {
                                CoachAthleteDetailView(athleteId: card.athleteId)
                            } label: {
                                AthleteCardView(athlete: card, showsNextEvent: model.filters.playingWithin != nil)
                            }
                            .listRowBackground(Color.hubSurface)
                            .onAppear {
                                if card.id == model.items.last?.id {
                                    Task { if let programId { await model.loadMore(programId: programId) } }
                                }
                            }
                        }
                        if model.isLoadingMore {
                            HStack { Spacer(); ProgressView().tint(Color.hubPrimary); Spacer() }
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text(model.total == 1 ? "1 athlete" : "\(model.total) athletes")
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .refreshable { await runIfPossible() }
            }
        }
    }

    private var activeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.filters.chipLabels, id: \.self) { chip in
                    Text(chip)
                        .font(.caption.bold())
                        .foregroundStyle(Color.hubPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.hubPrimary.opacity(0.12))
                        .clipShape(Capsule())
                }
                Button("Clear all") { model.filters = DiscoverFilters() }
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubTextSecondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubTextSecondary)
            Text(model.filters.activeCount > 0 || !model.queryText.isEmpty
                 ? "No athletes match. Try widening the radius or clearing a filter."
                 : "No published athletes in \(programs.selectedContext?.programLabel.lowercased() ?? "this program") yet.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if model.filters.activeCount > 0 {
                Button("Clear filters") { model.filters = DiscoverFilters() }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.hubPrimary)
            }
        }
    }
}

/// Shown on any coach tab while no valid program context exists (suspension
/// mid-session, membership change). The resolver handles the next launch.
struct CoachAccessUnavailableView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(Color.hubWarning)
            Text("Your program access is being updated")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Coach Mode needs a verified program. If this persists, contact \(HubSupport.email).")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task {
                    if let userId = authViewModel.session?.user.id.uuidString {
                        await programs.refresh(coachUserId: userId)
                    }
                }
            }
            .font(.subheadline.bold())
            .foregroundStyle(Color.hubPrimary)
        }
    }
}
