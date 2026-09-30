import SwiftUI

/// Admin queue of College Coach applications. Approval, rejection and
/// requests for more information happen on the detail screen, always via the
/// server-side RPCs — never by editing status directly.
struct CoachApplicationsView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case needsReview = "Needs review"
        case approved = "Approved"
        case other = "Other"

        var id: String { rawValue }

        func matches(_ status: CoachRequestStatus) -> Bool {
            switch self {
            case .needsReview: status == .pending || status == .needsMoreInformation
            case .approved: status == .approved
            case .other: status == .rejected || status == .withdrawn
            }
        }
    }

    @State private var requests: [CoachRequest] = []
    @State private var filter: Filter = .needsReview
    @State private var isLoading = true
    @State private var loadFailed = false

    private var visible: [CoachRequest] {
        requests.filter { filter.matches($0.status) }
    }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            VStack(spacing: 12) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(label(for: f)).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if isLoading && requests.isEmpty {
                    Spacer()
                    ProgressView().tint(Color.hubPrimary)
                    Spacer()
                } else if loadFailed && requests.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("Couldn't load applications.")
                            .foregroundStyle(Color.hubTextSecondary)
                        Button("Try Again") { Task { await load() } }
                            .foregroundStyle(Color.hubPrimary)
                    }
                    Spacer()
                } else if visible.isEmpty {
                    Spacer()
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                } else {
                    List {
                        ForEach(visible) { request in
                            NavigationLink {
                                CoachApplicationDetailView(requestId: request.id) { updated in
                                    replace(updated)
                                }
                            } label: {
                                CoachApplicationRow(request: request)
                            }
                            .listRowBackground(Color.hubSurface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .refreshable { await load() }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Coach Applications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func label(for filter: Filter) -> String {
        let count = requests.filter { filter.matches($0.status) }.count
        return count > 0 ? "\(filter.rawValue) (\(count))" : filter.rawValue
    }

    private var emptyText: String {
        switch filter {
        case .needsReview: "No applications waiting for review."
        case .approved: "No approved coaches yet."
        case .other: "No rejected or withdrawn applications."
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await CoachAdminService.shared.fetchRequests()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func replace(_ updated: CoachRequest) {
        if let index = requests.firstIndex(where: { $0.id == updated.id }) {
            requests[index] = updated
        } else {
            requests.insert(updated, at: 0)
        }
    }
}

private struct CoachApplicationRow: View {
    let request: CoachRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(request.fullName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                CoachStatusPill(status: request.status)
            }
            Text([request.title, request.college].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(request.programLabel)
                if let division = request.divisionLabel {
                    Text("·")
                    Text(division)
                }
                Spacer()
                Text((request.resubmittedAt ?? request.createdAt).asFormattedDate())
            }
            .font(.caption)
            .foregroundStyle(Color.hubTextSecondary)
        }
        .padding(.vertical, 4)
    }
}

/// Status chip shared by admin list/detail.
struct CoachStatusPill: View {
    let status: CoachRequestStatus

    private var tint: Color {
        switch status {
        case .pending: Color.hubPrimary
        case .approved: Color.hubSuccess
        case .rejected, .needsMoreInformation: Color.hubWarning
        case .withdrawn: Color.hubTextSecondary
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15))
            .clipShape(Capsule())
    }
}
