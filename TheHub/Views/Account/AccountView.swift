import SwiftUI
import Auth

/// Account management: identity, blocked people, and in-app account deletion
/// (Apple guideline 5.1.1(v) — apps with account creation must offer deletion).
struct AccountView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var blocks: [UserBlock] = []
    @State private var blockedNames: [String: CoachDirectoryEntry] = [:]
    @State private var blocksLoadFailed = false
    @State private var showDeleteConfirm = false
    @State private var deleteConfirmationText = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var legalDocument: LegalDocument?

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    accountCard
                    blockedPeopleCard
                    legalCard
                    deleteCard
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBlocks() }
        .sheet(item: $legalDocument) { document in
            LegalView(document: document)
        }
    }

    private var userId: String? {
        authViewModel.session?.user.id.uuidString
    }

    private func loadBlocks() async {
        guard let userId else { return }
        do {
            blocks = try await SafetyService.shared.listBlocks(userId: userId)
            blocksLoadFailed = false
        } catch {
            // "You haven't blocked anyone" would be wrong after a failed fetch —
            // an athlete could believe a block is gone when it isn't.
            blocksLoadFailed = true
            return
        }
        let coaches = (try? await AthleteService.shared.fetchCoachNames(
            userIds: blocks.map(\.blockedUserId)
        )) ?? []
        blockedNames = Dictionary(uniqueKeysWithValues: coaches.map { ($0.userId, $0) })
    }

    // MARK: - Cards

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signed In As")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            Text(authViewModel.session?.user.email ?? "—")
                .font(.subheadline)
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                ForEach(authViewModel.currentRoles, id: \.self) { role in
                    Text(role.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.hubSurfaceElevated)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var blockedPeopleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blocked People")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            if blocksLoadFailed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.hubWarning)
                    Text("Couldn't load your block list.")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Retry") {
                        Task { await loadBlocks() }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.hubPrimary)
                }
            } else if blocks.isEmpty {
                Text("You haven't blocked anyone. You can block someone from any conversation.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            } else {
                ForEach(blocks) { block in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(blockedNames[block.blockedUserId]?.coachName ?? "Blocked user")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            if let college = blockedNames[block.blockedUserId]?.college {
                                Text(college)
                                    .font(.caption)
                                    .foregroundStyle(Color.hubTextSecondary)
                            }
                        }
                        Spacer()
                        Button("Unblock") {
                            Task {
                                guard let userId else { return }
                                try? await SafetyService.shared.unblock(
                                    userId: userId,
                                    blockedUserId: block.blockedUserId
                                )
                                await loadBlocks()
                            }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.hubPrimary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Legal")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            Button {
                legalDocument = .terms
            } label: {
                HStack {
                    Text("Terms of Service")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            .padding(.vertical, 4)

            Button {
                legalDocument = .privacyPolicy
            } label: {
                HStack {
                    Text("Privacy Policy")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete Account")
                .font(.headline)
                .foregroundStyle(Color.hubError)

            Text("Deleting your account permanently removes your sign-in, athlete profile, photos and highlight links, schedule, target school list, messages, bookmarks and notifications. This cannot be undone. If you just want a break, unpublish your profile instead.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)

            if showDeleteConfirm {
                HubTextField(label: "Type DELETE to confirm", text: $deleteConfirmationText, autocapitalization: .characters)

                if let errorMessage {
                    HubErrorText(message: errorMessage)
                }

                Button {
                    Task { await deleteAccount() }
                } label: {
                    Group {
                        if isDeleting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Permanently Delete My Account")
                                .font(.subheadline.bold())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .foregroundStyle(.white)
                .background(Color.hubError.opacity(confirmed ? 1 : 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(!confirmed || isDeleting)

                Button("Cancel") {
                    showDeleteConfirm = false
                    deleteConfirmationText = ""
                    errorMessage = nil
                }
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .frame(maxWidth: .infinity)
            } else {
                Button("Delete my account…") {
                    showDeleteConfirm = true
                }
                .font(.subheadline.bold())
                .foregroundStyle(Color.hubError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var confirmed: Bool {
        deleteConfirmationText.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE"
    }

    private func deleteAccount() async {
        guard confirmed else {
            errorMessage = "Type DELETE to confirm."
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await AuthService.shared.deleteAccount()
            await authViewModel.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
