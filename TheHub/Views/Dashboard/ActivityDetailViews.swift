import SwiftUI

// Drill-in screens behind the dashboard activity tiles: which coaches
// bookmarked the profile, and the message threads. (Views tile opens Insights.)

// MARK: - Bookmarks

struct BookmarksView: View {
    let athlete: Athlete

    @State private var bookmarks: [BookmarkSummary] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color.hubPrimary)
            } else if loadFailed {
                LoadErrorState { await load() }
            } else if bookmarks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        Text("These coaches saved your profile to their recruiting shortlist.")
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        ForEach(bookmarks) { bookmark in
                            bookmarkRow(bookmark)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Coach Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            bookmarks = try await AthleteService.shared.fetchBookmarks(athleteId: athlete.id)
            loadFailed = false
        } catch {
            // Don't render "No bookmarks yet" over a network failure —
            // it reads as coaches having disappeared.
            loadFailed = true
        }
        isLoading = false
    }

    private func bookmarkRow(_ bookmark: BookmarkSummary) -> some View {
        HStack(spacing: 12) {
            CollegeCrestView(collegeName: bookmark.college ?? "")

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.coachName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text([bookmark.title, bookmark.college].compactMap(\.self).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            }

            Spacer()

            Text(bookmark.savedAt.asFormattedDate())
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .padding(14)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 40))
                .foregroundStyle(Color.hubTextSecondary)
            Text("No bookmarks yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("When a coach saves your profile to their pipeline, you'll see them here.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Message threads

struct ThreadsView: View {
    let athlete: Athlete
    let currentUserId: String

    struct Thread: Identifiable {
        let coachUserId: String
        var coach: CoachDirectoryEntry?
        var messages: [Message]

        var id: String { coachUserId }
        var lastMessage: Message? { messages.last }
        func unreadCount(currentUserId: String) -> Int {
            messages.count { $0.readAt == nil && $0.senderUserId != currentUserId }
        }
    }

    @State private var threads: [Thread] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color.hubPrimary)
            } else if loadFailed {
                LoadErrorState { await load() }
            } else if threads.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(threads) { thread in
                            NavigationLink {
                                ThreadDetailView(
                                    athlete: athlete,
                                    currentUserId: currentUserId,
                                    thread: thread
                                )
                            } label: {
                                threadRow(thread)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            let messages = try await AthleteService.shared.fetchMessages(athleteId: athlete.id)
            var grouped: [String: [Message]] = [:]
            for message in messages {
                grouped[message.coachUserId, default: []].append(message)
            }
            // Coach names are decorative — a failure there shouldn't hide messages
            let coaches = (try? await AthleteService.shared.fetchCoachNames(userIds: Array(grouped.keys))) ?? []
            let coachById = Dictionary(uniqueKeysWithValues: coaches.map { ($0.userId, $0) })

            threads = grouped
                .map { Thread(coachUserId: $0.key, coach: coachById[$0.key], messages: $0.value) }
                .sorted {
                    ($0.lastMessage?.createdAt ?? "") > ($1.lastMessage?.createdAt ?? "")
                }
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func threadRow(_ thread: Thread) -> some View {
        HStack(spacing: 12) {
            CollegeCrestView(collegeName: thread.coach?.college ?? "")

            VStack(alignment: .leading, spacing: 3) {
                Text(thread.coach?.coachName ?? "College coach")
                    .font(.headline)
                    .foregroundStyle(.white)
                if let college = thread.coach?.college {
                    Text(college)
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
                if let last = thread.lastMessage {
                    Text(last.body)
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            let unread = thread.unreadCount(currentUserId: currentUserId)
            if unread > 0 {
                Text("\(unread)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.hubPrimary)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 40))
                .foregroundStyle(Color.hubTextSecondary)
            Text("No messages yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("When coaches reach out, their messages show up here.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

struct ThreadDetailView: View {
    let athlete: Athlete
    let currentUserId: String
    let thread: ThreadsView.Thread

    @State private var messages: [Message]
    @State private var isBlocked = false
    @State private var showBlockConfirm = false
    @State private var showReportSheet = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var isUpdatingBlock = false
    @State private var actionError: String?

    init(athlete: Athlete, currentUserId: String, thread: ThreadsView.Thread) {
        self.athlete = athlete
        self.currentUserId = currentUserId
        self.thread = thread
        _messages = State(initialValue: thread.messages)
    }

    private var visibleMessages: [Message] {
        // When the athlete blocked this coach, hide the coach's messages (web parity)
        isBlocked ? messages.filter { $0.senderUserId != thread.coachUserId } : messages
    }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if isBlocked {
                            blockedBanner
                        }

                        ForEach(visibleMessages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                // Open at the newest message, and follow along when one is
                // sent — otherwise a sent message renders off-screen.
                .onAppear { scrollToLatest(proxy, animated: false) }
                .onChange(of: messages.count) { scrollToLatest(proxy, animated: true) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isBlocked {
                composeBar
            }
        }
        .alert("Something Went Wrong", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(actionError ?? "")
        }
        .navigationTitle(thread.coach?.coachName ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showReportSheet = true
                    } label: {
                        Label("Report Conversation", systemImage: "flag")
                    }
                    if isBlocked {
                        Button {
                            Task { await setBlocked(false) }
                        } label: {
                            Label("Unblock This Coach", systemImage: "hand.raised.slash")
                        }
                    } else {
                        Button(role: .destructive) {
                            showBlockConfirm = true
                        } label: {
                            Label("Block This Coach", systemImage: "hand.raised")
                        }
                    }
                } label: {
                    if isUpdatingBlock {
                        ProgressView().tint(Color.hubPrimary)
                    } else {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.hubPrimary)
                    }
                }
                .disabled(isUpdatingBlock)
                .accessibilityLabel("Conversation options")
            }
        }
        .confirmationDialog(
            "Block this coach?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { await setBlocked(true) }
            }
        } message: {
            Text("They won't be able to message you, and their messages will be hidden. You can unblock them anytime from this menu or Account.")
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(
                reporterUserId: currentUserId,
                targetType: "user",
                targetId: thread.coachUserId,
                athleteId: athlete.id,
                reportedUserId: thread.coachUserId
            )
        }
        .task {
            isBlocked = (try? await SafetyService.shared.isBlocked(
                userId: currentUserId,
                blockedUserId: thread.coachUserId
            )) ?? false
            // Opening the thread marks inbound messages as read
            try? await AthleteService.shared.markThreadRead(
                athleteId: athlete.id,
                coachUserId: thread.coachUserId,
                currentUserId: currentUserId
            )
        }
    }

    private func setBlocked(_ blocked: Bool) async {
        isUpdatingBlock = true
        defer { isUpdatingBlock = false }
        do {
            if blocked {
                try await SafetyService.shared.block(userId: currentUserId, blockedUserId: thread.coachUserId)
            } else {
                try await SafetyService.shared.unblock(userId: currentUserId, blockedUserId: thread.coachUserId)
            }
            isBlocked = blocked
        } catch {
            // A safety action failing silently is worse than an interruption —
            // tell the user so they know the block/unblock did NOT happen.
            actionError = blocked
                ? "Couldn't block this coach. Check your connection and try again."
                : "Couldn't unblock this coach. Check your connection and try again."
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = visibleMessages.last else { return }
        if animated {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Compose

    private var composeBar: some View {
        VStack(spacing: 6) {
            // Athlete outreach is always allowed here; the coach's reply may
            // be limited by their recruiting window (spec §18).
            Text("You can message coaches anytime. NCAA rules may limit how a coach can reply before their recruiting window opens.")
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            HStack(spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.hubSurface)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().tint(Color.hubPrimary)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(draft.isBlank ? Color.hubTextSecondary : Color.hubPrimary)
                    }
                }
                .disabled(draft.isBlank || isSending)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.hubBackground)
    }

    private func send() async {
        let body = draft.trimmed
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await AthleteService.shared.sendMessage(
                athleteId: athlete.id,
                coachUserId: thread.coachUserId,
                senderUserId: currentUserId,
                body: body
            )
            messages.append(message)
            draft = ""
        } catch let recruiting as RecruitingRulesError {
            // The database rejected the send under a verified recruiting rule.
            // Server result is authoritative; show its reason (spec §18).
            actionError = recruiting.userMessage
        } catch {
            actionError = "Your message couldn't be sent. Check your connection and try again."
        }
    }

    private var blockedBanner: some View {
        VStack(spacing: 8) {
            Label("You blocked this coach. Their messages are hidden and they can't contact you.", systemImage: "hand.raised.fill")
                .font(.caption)
                .foregroundStyle(Color.hubWarning)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Unblock") {
                Task { await setBlocked(false) }
            }
            .font(.caption.bold())
            .foregroundStyle(Color.hubPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.hubWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func bubble(_ message: Message) -> some View {
        let inbound = message.senderUserId == thread.coachUserId

        HStack {
            if !inbound { Spacer(minLength: 48) }
            VStack(alignment: inbound ? .leading : .trailing, spacing: 4) {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(inbound ? Color.hubSurfaceElevated : Color.hubPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(message.createdAt.asFormattedDate())
                    .font(.caption2)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            if inbound { Spacer(minLength: 48) }
        }
    }
}

// MARK: - Shared load-failure state

/// Network-failure state with retry — shown instead of a misleading empty
/// state ("No messages yet") when a fetch actually failed.
struct LoadErrorState: View {
    let retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.hubWarning)
            Text("Couldn't load")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task {
                    isRetrying = true
                    await retry()
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView().tint(Color.hubPrimary)
                } else {
                    Text("Try Again").bold()
                }
            }
            .foregroundStyle(Color.hubPrimary)
        }
    }
}

// MARK: - Report sheet (Apple 1.2 — UGC reporting)

struct ReportSheet: View {
    let reporterUserId: String
    let targetType: String
    let targetId: String
    let athleteId: String?
    let reportedUserId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var reason = SafetyService.reportReasons[0]
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                if didSubmit {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.hubSuccess)
                        Text("Report Sent")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Our team reviews reports within 24 hours.")
                            .font(.subheadline)
                            .foregroundStyle(Color.hubTextSecondary)
                        Button("Done") { dismiss() }
                            .foregroundStyle(Color.hubPrimary)
                            .fontWeight(.semibold)
                            .padding(.top, 8)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What's wrong?")
                                .font(.headline)
                                .foregroundStyle(.white)

                            VStack(spacing: 0) {
                                ForEach(SafetyService.reportReasons, id: \.self) { option in
                                    Button {
                                        reason = option
                                    } label: {
                                        HStack {
                                            Image(systemName: reason == option ? "largecircle.fill.circle" : "circle")
                                                .foregroundStyle(Color.hubPrimary)
                                            Text(option)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                    }
                                    Divider().background(Color.hubBorder)
                                }
                            }
                            .background(Color.hubSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Details (optional)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.hubTextSecondary)
                                TextEditor(text: $details)
                                    .frame(minHeight: 90)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.hubSurface)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .onChange(of: details) {
                                        details = String(details.prefix(2000))
                                    }
                            }

                            if let errorMessage {
                                HubErrorText(message: errorMessage)
                            }

                            HubPrimaryButton("Send Report", isLoading: isSubmitting) {
                                Task { await submit() }
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.hubPrimary)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await SafetyService.shared.submitReport(
                reporterUserId: reporterUserId,
                targetType: targetType,
                targetId: targetId,
                athleteId: athleteId,
                reportedUserId: reportedUserId,
                reason: reason,
                details: details.isBlank ? nil : details
            )
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
