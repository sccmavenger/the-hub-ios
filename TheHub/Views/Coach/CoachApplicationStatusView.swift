import SwiftUI

/// What a coach applicant sees after signing in, until approval: the claims
/// under review, the current status, and the way forward (edit / resubmit /
/// withdraw). Never shows athlete content — the account has no coach role.
struct CoachApplicationStatusView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    let request: CoachRequest

    @State private var showEdit = false
    @State private var showWithdrawConfirm = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    programCard
                    statusCard
                    whyCard
                    if let errorMessage {
                        HubErrorText(message: errorMessage)
                    }
                    actions
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .refreshable { await authViewModel.refreshCoachRequest() }
        }
        .navigationTitle("Coach Verification")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                CoachApplicationEditView(request: request)
            }
        }
        .confirmationDialog(
            "Withdraw your application?",
            isPresented: $showWithdrawConfirm,
            titleVisibility: .visible
        ) {
            Button("Withdraw Application", role: .destructive) {
                Task { await withdraw() }
            }
        } message: {
            Text("Your account stays active. You can submit a new application later.")
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: headerIcon)
                .font(.system(size: 56))
                .foregroundStyle(headerTint)
            Text(headline)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subheadline)
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var programCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Program under review")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)
            Text(request.college ?? "Institution not provided")
                .font(.headline)
                .foregroundStyle(.white)
            Text(request.programLabel)
                .foregroundStyle(.white)
            if let division = request.divisionLabel {
                Text(division)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            if let title = request.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Status")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.hubTextSecondary)
                Spacer()
                Text(request.status.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(headerTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(headerTint.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack {
                Text("Submitted")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                Spacer()
                Text(request.createdAt.asFormattedDate(style: .long))
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            if let resubmitted = request.resubmittedAt {
                HStack {
                    Text("Resubmitted")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                    Spacer()
                    Text(resubmitted.asFormattedDate(style: .long))
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }

            if let message = reviewMessage {
                Divider().background(Color.hubBorder)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reviewMessageLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.hubTextSecondary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var whyCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Why verification is required")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("The Hub limits athlete recruiting access to approved college coaches. Every application is reviewed by a person and tied to a verified college basketball program.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        } icon: {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(Color.hubPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            switch request.status {
            case .pending:
                HubPrimaryButton("Review Application", isLoading: isWorking) { showEdit = true }
                withdrawButton
            case .needsMoreInformation:
                HubPrimaryButton("Update Application", isLoading: isWorking) { showEdit = true }
                withdrawButton
            case .rejected:
                HubPrimaryButton("Update & Resubmit", isLoading: isWorking) { showEdit = true }
            case .withdrawn:
                HubPrimaryButton("Submit Again", isLoading: isWorking) { showEdit = true }
            case .approved:
                if let url = URL(string: "mailto:\(HubSupport.email)?subject=Coach%20access%20paused") {
                    Link(destination: url) {
                        Text("Contact Support")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .background(Color.hubPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Button("Sign Out") {
                Task { await authViewModel.signOut() }
            }
            .font(.subheadline)
            .foregroundStyle(Color.hubTextSecondary)
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private var withdrawButton: some View {
        Button("Withdraw Application") { showWithdrawConfirm = true }
            .font(.subheadline)
            .foregroundStyle(Color.hubError)
            .disabled(isWorking)
    }

    private func withdraw() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await CoachOnboardingService.shared.withdrawApplication()
            authViewModel.applyCoachRequest(updated)
        } catch {
            errorMessage = "Couldn't withdraw the application. \(error.localizedDescription)"
        }
    }

    // MARK: - Copy per status

    private var headerIcon: String {
        switch request.status {
        case .pending: "clock.badge"
        case .needsMoreInformation: "questionmark.circle"
        case .rejected: "exclamationmark.triangle"
        case .withdrawn: "arrow.uturn.backward.circle"
        case .approved: "pause.circle"
        }
    }

    private var headerTint: Color {
        switch request.status {
        case .pending: Color.hubPrimary
        case .needsMoreInformation, .rejected: Color.hubWarning
        case .withdrawn: Color.hubTextSecondary
        case .approved: Color.hubWarning
        }
    }

    private var headline: String {
        switch request.status {
        case .pending: "Your account is active."
        case .needsMoreInformation: "We need a little more information."
        case .rejected: "Your application needs attention."
        case .withdrawn: "You withdrew your application."
        case .approved: "Your coach access is paused."
        }
    }

    private var subheadline: String {
        switch request.status {
        case .pending:
            "We're verifying your affiliation with the program below. We'll notify you when Coach Mode is available."
        case .needsMoreInformation:
            "Review the note below, update your application, and we'll take another look."
        case .rejected:
            "We couldn't verify your affiliation with the information provided. Update your application to try again."
        case .withdrawn:
            "Your account stays active. Submit a new application whenever you're ready."
        case .approved:
            "Your verified program membership is no longer active. If you've changed schools or believe this is an error, contact support."
        }
    }

    private var reviewMessage: String? {
        switch request.status {
        case .rejected: request.rejectionReason
        case .needsMoreInformation: request.infoRequestMessage
        default: nil
        }
    }

    private var reviewMessageLabel: String {
        request.status == .rejected ? "Reason" : "What we need"
    }
}
