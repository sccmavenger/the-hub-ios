import SwiftUI
import Auth
import Supabase

/// Coach inbox (spec §13): one row per athlete the coach has a thread with,
/// scoped to the selected program's sport and gender, excluding athletes who
/// blocked this coach. Everything comes from `coach_inbox`.
struct CoachInboxView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared
    @State private var threads: [CoachInboxThread] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var programId: String? { programs.selectedContext?.programId }
    private var userId: String? { authViewModel.session?.user.id.uuidString }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            if programId == nil {
                CoachAccessUnavailableView()
            } else if isLoading && threads.isEmpty {
                ProgressView().tint(Color.hubPrimary)
            } else if let errorMessage, threads.isEmpty {
                VStack(spacing: 12) {
                    Text(errorMessage).font(.subheadline).foregroundStyle(Color.hubTextSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                    Button("Try Again") { Task { await load() } }.font(.subheadline.bold()).foregroundStyle(Color.hubPrimary)
                }
            } else if threads.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(threads) { thread in
                        NavigationLink {
                            CoachThreadView(athlete: thread.athlete)
                        } label: {
                            row(thread)
                        }
                        .listRowBackground(Color.hubSurface)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { CoachProgramChip() }
        }
        .task(id: programId) { await load() }
    }

    private func row(_ thread: CoachInboxThread) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HubRemoteImage(path: thread.athlete.profilePhotoPath) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.hubTextSecondary)
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.athlete.fullName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let last = thread.lastMessage {
                        Text(last.createdAt.asFormattedDate())
                            .font(.caption2)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                }
                Text([thread.athlete.classLabel, thread.athlete.position].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                if let last = thread.lastMessage {
                    Text((last.senderUserId == userId ? "You: " : "") + last.body)
                        .font(.subheadline)
                        .foregroundStyle(thread.unreadCount > 0 ? .white : Color.hubTextSecondary)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .trailing, spacing: 6) {
                if thread.unreadCount > 0 {
                    Text("\(thread.unreadCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.hubPrimary)
                        .clipShape(Capsule())
                }
                if let stage = thread.boardPipelineStage {
                    Text(stage.displayName)
                        .font(.caption2.bold())
                        .foregroundStyle(stage.color)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubTextSecondary)
            Text("No conversations yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Athletes can message you first. You can message an athlete from their profile when the recruiting rules for your program allow it.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func load() async {
        guard let programId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            threads = try await CoachWorkspaceService.shared.inbox(programId: programId)
            errorMessage = nil
        } catch {
            errorMessage = CoachDiscoverModel.message(for: error)
        }
    }
}
