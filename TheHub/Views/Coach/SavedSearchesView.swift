import SwiftUI

/// Personal, program-scoped saved Discover filters (spec §8.5, D27) with the
/// per-search alerts opt-in (D13): an hourly server job notifies about
/// athletes newly matching, deduped against what the coach has already seen.
struct SavedSearchesView: View {
    @Environment(\.dismiss) private var dismiss
    let programId: String
    let coachUserId: String
    /// The filters currently applied in Discover, offered for saving.
    let current: DiscoverFilters
    let onRun: (CoachSavedSearch) -> Void

    @State private var searches: [CoachSavedSearch] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNamePrompt = false
    @State private var newName = ""
    @State private var renaming: CoachSavedSearch?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()
                List {
                    if !current.isEmpty {
                        Section {
                            Button {
                                newName = ""
                                showNamePrompt = true
                            } label: {
                                Label("Save current filters", systemImage: "plus.circle.fill")
                                    .foregroundStyle(Color.hubPrimary)
                            }
                            .listRowBackground(Color.hubSurface)
                        } footer: {
                            Text(current.chipLabels.joined(separator: " · "))
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                    }

                    Section {
                        if isLoading {
                            HStack { Spacer(); ProgressView().tint(Color.hubPrimary); Spacer() }
                                .listRowBackground(Color.clear)
                        } else if searches.isEmpty {
                            Text("No saved searches for this program yet.")
                                .font(.subheadline)
                                .foregroundStyle(Color.hubTextSecondary)
                                .listRowBackground(Color.hubSurface)
                        }
                        ForEach(searches) { saved in
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    onRun(saved)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(saved.name)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text(saved.filters.chipLabels.isEmpty ? "All athletes" : saved.filters.chipLabels.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(Color.hubTextSecondary)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Toggle(isOn: Binding(
                                    get: { saved.alertsEnabled },
                                    set: { enabled in Task { await setAlerts(saved, enabled: enabled) } }
                                )) {
                                    Text(saved.alertsEnabled ? "Alerting hourly on new matches" : "Alert me about new matches")
                                        .font(.caption)
                                        .foregroundStyle(Color.hubTextSecondary)
                                }
                                .tint(Color.hubPrimary)
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(Color.hubSurface)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await delete(saved) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    renaming = saved
                                    renameText = saved.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(Color.hubPrimary)
                            }
                        }
                    } header: {
                        Text("Saved searches")
                            .foregroundStyle(Color.hubTextSecondary)
                    } footer: {
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(Color.hubError)
                        } else {
                            Text("Saved searches are yours alone and scoped to this program.")
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Saved Searches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .alert("Name this search", isPresented: $showNamePrompt) {
                TextField("e.g. 2028 guards near STL", text: $newName)
                Button("Save") { Task { await saveCurrent() } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename search", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") { Task { await rename() } }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            searches = try await CoachWorkspaceService.shared.savedSearches(programId: programId)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load saved searches."
        }
    }

    private func saveCurrent() async {
        let name = newName.trimmed
        guard !name.isEmpty else { return }
        do {
            let saved = try await CoachWorkspaceService.shared.createSavedSearch(
                coachUserId: coachUserId, programId: programId, name: name, filters: current
            )
            searches.insert(saved, at: 0)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save the search. \(error.localizedDescription)"
        }
    }

    private func rename() async {
        guard let target = renaming else { return }
        let name = renameText.trimmed
        renaming = nil
        guard !name.isEmpty, name != target.name else { return }
        do {
            try await CoachWorkspaceService.shared.renameSavedSearch(id: target.id, name: name)
            if let index = searches.firstIndex(where: { $0.id == target.id }) {
                searches[index].name = name
            }
        } catch {
            errorMessage = "Couldn't rename the search."
        }
    }

    private func setAlerts(_ saved: CoachSavedSearch, enabled: Bool) async {
        guard let index = searches.firstIndex(where: { $0.id == saved.id }) else { return }
        let previous = searches[index].alertsEnabled
        searches[index].alertsEnabled = enabled
        do {
            try await CoachWorkspaceService.shared.setSavedSearchAlerts(id: saved.id, enabled: enabled)
            errorMessage = nil
        } catch {
            searches[index].alertsEnabled = previous
            errorMessage = "Couldn't update alerts for “\(saved.name)”."
        }
    }

    private func delete(_ saved: CoachSavedSearch) async {
        do {
            try await CoachWorkspaceService.shared.deleteSavedSearch(id: saved.id)
            searches.removeAll { $0.id == saved.id }
        } catch {
            errorMessage = "Couldn't delete the search."
        }
    }
}
