import SwiftUI
import Auth
import Supabase

/// A coach's conversation with one athlete (spec §13; rules spec §18).
/// Preflight shows the rules engine's decision for this program and athlete;
/// the send goes through `send_coach_message`, which is authoritative: a
/// denial is shown with the server's reason and the preflight is refreshed.
/// Opens a thread from a notification, where only the athlete id is known:
/// loads the allowlisted card through `coach_athlete_detail` (which enforces
/// program, publication and blocks) and then shows the thread.
struct CoachThreadLoaderView: View {
    let athleteId: String

    @State private var programs = CoachProgramService.shared
    @State private var athlete: CoachAthleteCard?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            if let athlete {
                CoachThreadView(athlete: athlete)
            } else if failed {
                VStack(spacing: 12) {
                    Text("This conversation isn't available.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Try Again") { Task { await load() } }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.hubPrimary)
                }
            } else {
                ProgressView().tint(Color.hubPrimary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        guard let programId = programs.selectedContext?.programId else { failed = true; return }
        do {
            athlete = try await CoachWorkspaceService.shared.detail(programId: programId, athleteId: athleteId).athlete
        } catch {
            failed = true
        }
    }
}

struct CoachThreadView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared
    @State private var settings = AppSettingsService.shared
    let athlete: CoachAthleteCard

    @State private var messages: [Message] = []
    @State private var isLoading = true
    @State private var preflight: RecruitingStatusLoad = .loading
    @State private var draft = ""
    @State private var isSending = false
    @State private var actionError: String?
    @State private var showBlockConfirm = false
    @State private var didBlock = false
    @State private var showReport = false

    private var programId: String? { programs.selectedContext?.programId }
    private var userId: String? { authViewModel.session?.user.id.uuidString }

    /// With enforcement on, a hard-blocked decision will be refused server-side;
    /// disable Send so the coach isn't surprised. In shadow mode the send goes
    /// through, so warn instead.
    private var sendBlocked: Bool {
        if case .loaded(let decision) = preflight {
            return decision.wouldHardBlock && settings.recruitingRulesEnforcementEnabled
        }
        return false
    }

    private var shadowWarning: Bool {
        if case .loaded(let decision) = preflight {
            return decision.wouldHardBlock && !settings.recruitingRulesEnforcementEnabled
        }
        return false
    }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if isLoading && messages.isEmpty {
                ProgressView().tint(Color.hubPrimary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            if didBlock { blockedBanner }
                            if messages.isEmpty {
                                Text("No messages yet. Say hello when the rules below allow it.")
                                    .font(.caption)
                                    .foregroundStyle(Color.hubTextSecondary)
                                    .padding(.top, 24)
                            }
                            ForEach(messages) { message in
                                bubble(message).id(message.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .onAppear { scrollToLatest(proxy, animated: false) }
                    .onChange(of: messages.count) { scrollToLatest(proxy, animated: true) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !didBlock { composeArea }
        }
        .navigationTitle(athlete.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        CoachAthleteDetailView(athleteId: athlete.athleteId)
                    } label: {
                        Label("View profile", systemImage: "person.crop.rectangle")
                    }
                    Button { showReport = true } label: { Label("Report", systemImage: "flag") }
                    if didBlock {
                        Button { Task { await setBlocked(false) } } label: { Label("Unblock athlete", systemImage: "hand.raised.slash") }
                    } else {
                        Button(role: .destructive) { showBlockConfirm = true } label: { Label("Block athlete", systemImage: "hand.raised") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Color.hubPrimary)
                }
                .accessibilityLabel("Conversation options")
            }
        }
        .alert("Message Not Sent", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") {}
        } message: {
            Text(actionError ?? "")
        }
        .alert("Block this athlete?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) { Task { await setBlocked(true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Neither of you will be able to message the other. You can unblock from this menu.")
        }
        .sheet(isPresented: $showReport) {
            if let userId {
                ReportSheet(reporterUserId: userId, targetType: "athlete_profile", targetId: athlete.athleteId, athleteId: athlete.athleteId, reportedUserId: nil)
            }
        }
        .task(id: programId) {
            await load()
            await refreshPreflight()
        }
    }

    // MARK: - Compose

    private var composeArea: some View {
        VStack(spacing: 8) {
            RecruitingStatusView(title: "Recruiting rules for this athlete", load: preflight, showsSource: true, coachMode: true)
                .padding(12)
                .background(Color.hubSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if shadowWarning {
                Label("Enforcement is in shadow mode: this message would be blocked under the rule above. It will be delivered and recorded as prohibited.", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(Color.hubWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                TextField(sendBlocked ? "Sending opens on the date above" : "Message", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.hubSurface)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .disabled(sendBlocked)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().tint(Color.hubPrimary)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(draft.isBlank || sendBlocked ? Color.hubTextSecondary : Color.hubPrimary)
                    }
                }
                .disabled(draft.isBlank || isSending || sendBlocked)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.hubBackground)
    }

    private var blockedBanner: some View {
        VStack(spacing: 8) {
            Label("You blocked this athlete. Neither of you can message the other.", systemImage: "hand.raised.fill")
                .font(.caption)
                .foregroundStyle(Color.hubWarning)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Unblock") { Task { await setBlocked(false) } }
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
        let outbound = message.senderUserId == userId
        HStack {
            if outbound { Spacer(minLength: 48) }
            VStack(alignment: outbound ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(outbound ? Color.hubPrimary : Color.hubSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 6) {
                    Text(message.createdAt.asFormattedDate())
                    if outbound, let status = message.complianceStatus, status != "permitted" {
                        Text("· \(status.replacingOccurrences(of: "_", with: " "))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)
            }
            if !outbound { Spacer(minLength: 48) }
        }
    }

    // MARK: - Data

    private func load() async {
        guard let userId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // RLS narrows this to the signed-in coach's own thread with the athlete.
            messages = try await AthleteService.shared.fetchMessages(athleteId: athlete.athleteId)
            try? await AthleteService.shared.markThreadRead(athleteId: athlete.athleteId, coachUserId: userId, currentUserId: userId)
        } catch {
            actionError = "Couldn't load this conversation."
        }
    }

    private func refreshPreflight() async {
        preflight = .loading
        preflight = await RecruitingRulesService.shared.loadMyCoachAction(athleteId: athlete.athleteId, programId: programId)
    }

    private func send() async {
        guard let programId else { return }
        let body = draft.trimmed
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let result = try await CoachWorkspaceService.shared.sendMessage(programId: programId, athleteId: athlete.athleteId, body: body)
            switch result.status {
            case .sent:
                if let message = result.message { messages.append(message) }
                draft = ""
                if let decision = result.decision { preflight = .loaded(decision) }
            case .denied:
                // Server is authoritative (rules spec §18): show its reason, refresh preflight.
                actionError = result.decision?.userMessage ?? RecruitingRulesError.defaultProhibitedMessage
                if let decision = result.decision { preflight = .loaded(decision) } else { await refreshPreflight() }
            }
        } catch let recruiting as RecruitingRulesError {
            actionError = recruiting.userMessage
            await refreshPreflight()
        } catch {
            if let pg = error as? PostgrestError, pg.message.contains("blocked") {
                actionError = "This conversation is blocked."
            } else if let pg = error as? PostgrestError, pg.message == "not found" {
                actionError = "This athlete isn't available to your program anymore."
            } else {
                actionError = "Your message couldn't be sent. Check your connection and try again."
            }
        }
    }

    private func setBlocked(_ blocked: Bool) async {
        do {
            try await CoachWorkspaceService.shared.setAthleteBlocked(athleteId: athlete.athleteId, blocked: blocked)
            didBlock = blocked
        } catch {
            actionError = blocked ? "Couldn't block this athlete." : "Couldn't unblock this athlete."
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = messages.last else { return }
        if animated {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
