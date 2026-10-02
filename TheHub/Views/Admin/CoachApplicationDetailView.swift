import SwiftUI

/// One coach application: the applicant's claims, the review history, the
/// verified membership (once approved), and the admin actions. The claims are
/// starting points for verification — approval always names the program the
/// admin confirmed, never the free-text claim.
struct CoachApplicationDetailView: View {
    let requestId: String
    var onChange: (CoachRequest) -> Void = { _ in }

    @State private var request: CoachRequest?
    @State private var reviews: [CoachRequestReview] = []
    @State private var memberships: [CoachProgramMembership] = []
    @State private var loadFailed = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private enum Sheet: Identifiable {
        case approve, reject, requestInfo
        var id: Int { hashValue }
    }
    @State private var sheet: Sheet?
    @State private var membershipAction: (membership: CoachProgramMembership, status: CoachMembershipStatus)?

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if let request {
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard(request)
                        claimsCard(request)
                        if request.status == .approved || !memberships.isEmpty {
                            membershipsCard
                        }
                        if let message = request.rejectionReason ?? request.infoRequestMessage {
                            messageCard(request, message)
                        }
                        historyCard
                        if let errorMessage {
                            HubErrorText(message: errorMessage)
                        }
                        actions(request)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .refreshable { await load() }
            } else if loadFailed {
                VStack(spacing: 12) {
                    Text("Couldn't load this application.")
                        .foregroundStyle(Color.hubTextSecondary)
                    Button("Try Again") { Task { await load() } }
                        .foregroundStyle(Color.hubPrimary)
                }
            } else {
                ProgressView().tint(Color.hubPrimary)
            }
        }
        .navigationTitle("Application")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $sheet) { which in
            if let request {
                NavigationStack {
                    switch which {
                    case .approve:
                        CoachApprovalSheet(request: request) { await load() }
                    case .reject:
                        CoachReviewMessageSheet(request: request, mode: .reject) { await load() }
                    case .requestInfo:
                        CoachReviewMessageSheet(request: request, mode: .requestInfo) { await load() }
                    }
                }
            }
        }
        .alert(
            membershipDialogTitle,
            isPresented: Binding(get: { membershipAction != nil }, set: { if !$0 { membershipAction = nil } })
        ) {
            if let action = membershipAction {
                Button(action.status == .verified ? "Reinstate" : action.status.displayName.capitalized,
                       role: action.status == .verified ? nil : .destructive) {
                    Task { await setMembership(action.membership, to: action.status) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(membershipDialogMessage)
        }
    }

    // MARK: - Cards

    private func headerCard(_ request: CoachRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.fullName)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    if let url = URL(string: "mailto:\(request.email)") {
                        Link(request.email, destination: url)
                            .font(.subheadline)
                            .foregroundStyle(Color.hubPrimary)
                    }
                }
                Spacer()
                CoachStatusPill(status: request.status)
            }
            Divider().background(Color.hubBorder)
            detailRow("Submitted", request.createdAt.asFormattedDate(style: .long))
            if let resubmitted = request.resubmittedAt {
                detailRow("Resubmitted", resubmitted.asFormattedDate(style: .long))
            }
            if let reviewed = request.reviewedAt {
                detailRow("Reviewed", reviewed.asFormattedDate(style: .long))
            }
        }
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func claimsCard(_ request: CoachRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claimed affiliation")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)
            Text("Unverified — confirm against the school's staff directory before approving.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
            Divider().background(Color.hubBorder)
            detailRow("Title", request.title ?? "—")
            detailRow("Institution", request.college ?? "—")
            detailRow("Program", request.programLabel)
            detailRow("Association", request.governingBody ?? "—")
            detailRow("Division", request.division ?? "—")
            linkRow("Athletics URL", request.athleticsUrl)
            linkRow("Program URL", request.programUrl)
            detailRow("Phone", request.phone ?? "—")
            if let note = request.message, !note.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Applicant note")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var membershipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verified program membership")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)
            if memberships.isEmpty {
                Text("No membership rows found.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            ForEach(memberships) { membership in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(membership.program?.fullLabel ?? membership.programId)
                                .foregroundStyle(.white)
                            if let division = membership.program?.divisionLabel {
                                Text(division)
                                    .font(.caption)
                                    .foregroundStyle(Color.hubTextSecondary)
                            }
                            Text([membership.roleDisplayName, membership.title].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                        Spacer()
                        Text(membership.status.displayName)
                            .font(.caption2.bold())
                            .foregroundStyle(membership.status == .verified ? Color.hubSuccess : Color.hubWarning)
                    }
                    HStack(spacing: 16) {
                        if membership.status == .verified {
                            Button("Suspend") { membershipAction = (membership, .suspended) }
                                .foregroundStyle(Color.hubWarning)
                            Button("Mark Inactive") { membershipAction = (membership, .inactive) }
                                .foregroundStyle(Color.hubError)
                        } else {
                            Button("Reinstate") { membershipAction = (membership, .verified) }
                                .foregroundStyle(Color.hubSuccess)
                        }
                    }
                    .font(.caption.bold())
                    .disabled(isWorking)
                }
                .padding(.vertical, 4)
                if membership.id != memberships.last?.id {
                    Divider().background(Color.hubBorder)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func messageCard(_ request: CoachRequest, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(request.status == .rejected ? "Reason shown to applicant" : "Information requested")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)
            if reviews.isEmpty {
                Text("No review events.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            ForEach(reviews) { review in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(review.actionDisplayName)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(review.createdAt.asFormattedDate())
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                    if let note = review.internalNote, !note.isEmpty {
                        Text("Internal: \(note)")
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                    if let message = review.publicMessage, !message.isEmpty {
                        Text("To applicant: \(message)")
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(_ request: CoachRequest) -> some View {
        switch request.status {
        case .pending, .needsMoreInformation:
            VStack(spacing: 12) {
                HubPrimaryButton("Approve…", isLoading: isWorking) { sheet = .approve }
                HStack(spacing: 12) {
                    if request.status == .pending {
                        Button("Request Info…") { sheet = .requestInfo }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.hubSurface)
                            .foregroundStyle(Color.hubWarning)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button("Reject…") { sheet = .reject }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.hubSurface)
                        .foregroundStyle(Color.hubError)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .font(.subheadline.bold())
                .disabled(isWorking)
            }
            .padding(.top, 4)
        case .approved, .rejected, .withdrawn:
            Text(request.status == .approved
                 ? "Approved. Manage access through the membership above."
                 : "Waiting on the applicant to update and resubmit.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var membershipDialogTitle: String {
        switch membershipAction?.status {
        case .suspended: "Suspend this membership?"
        case .inactive: "Mark this membership inactive?"
        case .verified: "Reinstate this membership?"
        default: ""
        }
    }

    private var membershipDialogMessage: String {
        switch membershipAction?.status {
        case .suspended, .inactive:
            "The coach loses the coach role immediately unless another verified membership remains. History is kept."
        case .verified:
            "The coach regains Coach Mode access for this program."
        default: ""
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            let fetched = try await CoachAdminService.shared.fetchRequest(id: requestId)
            request = fetched
            onChange(fetched)
            loadFailed = false
            reviews = (try? await CoachAdminService.shared.fetchReviews(requestId: requestId)) ?? []
            memberships = (try? await CoachAdminService.shared.fetchMemberships(coachUserId: fetched.userId)) ?? []
        } catch {
            loadFailed = request == nil
        }
    }

    private func setMembership(_ membership: CoachProgramMembership, to status: CoachMembershipStatus) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await CoachAdminService.shared.setMembershipStatus(
                membershipId: membership.id, status: status, internalNote: nil
            )
            await load()
        } catch {
            errorMessage = "Couldn't update the membership. \(error.localizedDescription)"
        }
    }

    // MARK: - Rows

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.white)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func linkRow(_ label: String, _ value: String?) -> some View {
        if let value, let url = URL(string: value) {
            HStack(alignment: .top) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .frame(width: 96, alignment: .leading)
                Link(value, destination: url)
                    .font(.subheadline)
                    .foregroundStyle(Color.hubPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        } else {
            detailRow(label, "—")
        }
    }
}

// MARK: - Reject / request-info sheet

/// Collects the user-visible message (required) and an internal note.
struct CoachReviewMessageSheet: View {
    enum Mode {
        case reject, requestInfo
    }

    @Environment(\.dismiss) private var dismiss
    let request: CoachRequest
    let mode: Mode
    var onDone: () async -> Void = {}

    @State private var message = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text(mode == .reject
                         ? "The reason is shown to the applicant. Keep internal risk notes in the internal field."
                         : "Tell the applicant exactly what to add. They can update and resubmit from the app.")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HubMultilineField(
                        label: mode == .reject ? "Reason (shown to applicant)" : "What's needed (shown to applicant)",
                        text: $message,
                        placeholder: mode == .reject
                            ? "We could not verify your affiliation with the program information provided."
                            : "Please send a link to your listing in the staff directory.",
                        maxLength: 2000
                    )
                    HubMultilineField(label: "Internal note (admins only)", text: $note, maxLength: 2000)

                    if let errorMessage {
                        HubErrorText(message: errorMessage)
                    }
                    HubPrimaryButton(
                        mode == .reject ? "Reject Application" : "Send Request",
                        isLoading: isSaving,
                        isDisabled: message.isBlank
                    ) {
                        Task { await submit() }
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(mode == .reject ? "Reject" : "Request Information")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            switch mode {
            case .reject:
                _ = try await CoachAdminService.shared.reject(requestId: request.id, reason: message, internalNote: note)
            case .requestInfo:
                _ = try await CoachAdminService.shared.requestInfo(requestId: request.id, message: message, internalNote: note)
            }
            await onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
