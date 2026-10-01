import SwiftUI
import Auth
import Supabase

/// An athlete as a coach sees them (spec §8.3). Everything on screen comes
/// from `coach_athlete_detail`, which returns only the safe-field allowlist
/// and unlocks the contact card only while the program's board holds the
/// athlete (D25). Opening this screen records one profile view (W8).
struct CoachAthleteDetailView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared
    let athleteId: String

    @State private var detail: CoachAthleteDetail?
    @State private var loadFailed = false
    @State private var unavailable = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var photoViewer: PhotoViewerContext?
    @State private var showReport = false
    @State private var showRemoveConfirm = false

    // Board section (2D)
    @State private var tags: [String] = []
    @State private var staff: [ProgramStaffMember] = []
    @State private var noteDraft = ""
    @State private var noteSaved = false
    @State private var activity: [BoardActivity] = []

    private struct PhotoViewerContext: Identifiable {
        let id = UUID()
        let index: Int
    }

    private var programId: String? { programs.selectedContext?.programId }
    private var userId: String? { authViewModel.session?.user.id.uuidString }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if let detail {
                ScrollView {
                    VStack(spacing: 16) {
                        header(detail.athlete)
                        boardActions(detail)
                        if let entry = detail.board, !entry.isRemoved {
                            boardDetails(entry)
                            privateNoteCard
                            if !activity.isEmpty { activityCard }
                        }
                        if let bio = detail.athlete.bio, !bio.isBlank {
                            sectionCard("About") {
                                Text(bio).font(.subheadline).foregroundStyle(.white)
                            }
                        }
                        academics(detail.athlete)
                        if !detail.photos.isEmpty { photos(detail.photos) }
                        if !detail.videos.isEmpty { videos(detail.videos) }
                        schedule(detail.upcomingEvents)
                        contactCard(detail)
                        if let errorMessage {
                            HubErrorText(message: errorMessage)
                        }
                        reportButton
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .refreshable { await load() }
            } else if unavailable {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.hubTextSecondary)
                    Text("This profile isn't available.")
                        .foregroundStyle(.white)
                    Text("The athlete may have unpublished their profile or it isn't visible to your program.")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else if loadFailed {
                LoadErrorState(retry: { Task { await load() } })
            } else {
                ProgressView().tint(Color.hubPrimary)
            }
        }
        .navigationTitle(detail?.athlete.fullName ?? "Athlete")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: programId) {
            await load()
            await recordView()
        }
        .fullScreenCover(item: $photoViewer) { context in
            HubPhotoPager(items: (detail?.photos ?? []).map(HubPhotoItem.init), initialIndex: context.index)
        }
        .sheet(isPresented: $showReport) {
            if let userId {
                ReportSheet(reporterUserId: userId, targetType: "athlete_profile", targetId: athleteId, athleteId: athleteId, reportedUserId: nil)
            }
        }
        .confirmationDialog("Remove from the recruiting board?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
        } message: {
            Text("Your staff will no longer see this athlete on the board, and contact details lock again. You can restore them later.")
        }
    }

    // MARK: - Sections

    private func header(_ athlete: CoachAthleteCard) -> some View {
        VStack(spacing: 12) {
            HubRemoteImage(path: athlete.profilePhotoPath) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Color.hubTextSecondary)
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())

            Text(athlete.fullName)
                .font(.title2.bold())
                .foregroundStyle(.white)
            if let school = athlete.schoolLine {
                Text(school)
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            HubChipRow(chips: [
                athlete.position,
                athlete.classLabel,
                athlete.heightDisplay,
                athlete.weightLbs.map { "\($0) lbs" },
                athlete.jerseyNumber.map { "#\($0)" }
            ].compactMap { $0 })

            HStack(spacing: 16) {
                if let ig = athlete.instagramHandle, let url = URL(string: "https://instagram.com/\(ig.trimmingCharacters(in: CharacterSet(charactersIn: "@")))") {
                    Link(destination: url) { Label(ig, systemImage: "camera") }
                }
                if let tt = athlete.tiktokHandle, let url = URL(string: "https://tiktok.com/@\(tt.trimmingCharacters(in: CharacterSet(charactersIn: "@")))") {
                    Link(destination: url) { Label(tt, systemImage: "music.note") }
                }
            }
            .font(.caption)
            .foregroundStyle(Color.hubPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func boardActions(_ detail: CoachAthleteDetail) -> some View {
        if let entry = detail.board, !entry.isRemoved {
            VStack(spacing: 10) {
                HStack {
                    Label("On your board", systemImage: "rectangle.stack.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Menu {
                        ForEach(PipelineStage.allCases, id: \.self) { stage in
                            Button {
                                Task { await setStage(entry, stage) }
                            } label: {
                                if stage == entry.stage {
                                    Label(stage.displayName, systemImage: "checkmark")
                                } else {
                                    Text(stage.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(entry.stage.displayName)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(entry.stage.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(entry.stage.color.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .disabled(isWorking)
                }
                if let saver = entry.savedByName {
                    Text("Saved by \(saver)\(entry.assignedToName.map { " · Assigned to \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Remove from board") { showRemoveConfirm = true }
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubError)
                    .disabled(isWorking)
            }
            .padding(16)
            .background(Color.hubSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            HubPrimaryButton(detail.board?.isRemoved == true ? "Restore to Recruiting Board" : "Save to Recruiting Board",
                             isLoading: isWorking) {
                Task { await save() }
            }
        }
        NavigationLink {
            CoachThreadView(athlete: detail.athlete)
        } label: {
            Label("Message \(detail.athlete.fullName.split(separator: " ").first.map(String.init) ?? "athlete")", systemImage: "message")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .background(Color.hubSurface)
        .foregroundStyle(Color.hubPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Tags and assignee: shared with the whole staff (W5).
    private func boardDetails(_ entry: BoardEntry) -> some View {
        sectionCard("Board details") {
            Text("Tags")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
            TagEditor(tags: $tags) { cleaned in
                Task { await saveTags(entry, cleaned) }
            }

            Divider().background(Color.hubBorder)

            HStack {
                Text("Assigned to")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                Spacer()
                Menu {
                    Button("Unassigned") { Task { await assign(entry, nil) } }
                    ForEach(staff) { member in
                        Button {
                            Task { await assign(entry, member.userId) }
                        } label: {
                            if member.userId == entry.assignedTo {
                                Label(member.isMe ? "\(member.displayName) (you)" : member.displayName, systemImage: "checkmark")
                            } else {
                                Text(member.isMe ? "\(member.displayName) (you)" : member.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(entry.assignedToName ?? "Unassigned")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.hubPrimary)
                }
                .disabled(isWorking || staff.isEmpty)
            }
        }
    }

    /// Author-only (D11). Not shared with staff or admins.
    private var privateNoteCard: some View {
        sectionCard("Private note") {
            Text("Only you can see this. It stays with you if you change programs.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
            HubMultilineField(label: "", text: $noteDraft, placeholder: "Your evaluation, reminders, follow-ups…", lineRange: 3...10, maxLength: BoardEntry.maxNoteLength)
            HStack {
                Text("\(noteDraft.count)/\(BoardEntry.maxNoteLength)")
                    .font(.caption2)
                    .foregroundStyle(noteDraft.count > BoardEntry.maxNoteLength ? Color.hubError : Color.hubTextSecondary)
                Spacer()
                if noteSaved {
                    Label("Saved", systemImage: "checkmark").font(.caption).foregroundStyle(Color.hubSuccess)
                }
                Button("Save note") { Task { await saveNote() } }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.hubPrimary)
                    .disabled(isWorking || noteDraft.trimmed == (detail?.privateNote ?? ""))
            }
        }
    }

    private var activityCard: some View {
        sectionCard("Activity") {
            ForEach(activity) { row in
                HStack(alignment: .top) {
                    Text(row.summary)
                        .font(.caption)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(row.createdAt.asFormattedDate())
                        .font(.caption2)
                        .foregroundStyle(Color.hubTextSecondary)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func academics(_ athlete: CoachAthleteCard) -> some View {
        sectionCard("Academics") {
            HStack(spacing: 24) {
                stat("GPA", athlete.gpa.map { $0.formatted(.number.precision(.fractionLength(1...2))) })
                stat("Intended major", athlete.intendedMajor)
            }
        }
    }

    private func photos(_ photos: [CoachPhoto]) -> some View {
        sectionCard("Photos") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        photoViewer = PhotoViewerContext(index: index)
                    } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                HubRemoteImage(path: photo.storagePath) {
                                    Rectangle().fill(Color.hubSurfaceElevated)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.caption ?? "Action photo \(index + 1)")
                }
            }
        }
    }

    private func videos(_ videos: [CoachVideo]) -> some View {
        sectionCard("Videos") {
            ForEach(videos) { video in
                if let url = URL(string: video.url) {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "play.rectangle.fill").foregroundStyle(Color.hubPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.title ?? platformLabel(for: video.url))
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Text(platformLabel(for: video.url))
                                    .font(.caption)
                                    .foregroundStyle(Color.hubTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square").foregroundStyle(Color.hubTextSecondary)
                        }
                    }
                }
            }
        }
    }

    private func schedule(_ events: [CoachEvent]) -> some View {
        sectionCard("Upcoming schedule") {
            if events.isEmpty {
                Text("No games listed for the next 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.eventDate.asFormattedDate())
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        if let time = event.eventTime { Text(time).font(.caption).foregroundStyle(Color.hubTextSecondary) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.opponent.map { "vs \($0)" } ?? "Game")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        if let location = event.location {
                            Text(location).font(.caption).foregroundStyle(Color.hubTextSecondary)
                        }
                        if let notes = event.notes, !notes.isBlank {
                            Text(notes).font(.caption).foregroundStyle(Color.hubTextSecondary)
                        }
                    }
                    Spacer()
                    if event.isMayb == true {
                        Text("MAYB").font(.caption2.bold()).foregroundStyle(Color.hubPrimary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func contactCard(_ detail: CoachAthleteDetail) -> some View {
        sectionCard("Contact") {
            if detail.contactUnlocked, let contact = detail.contact {
                if contact.isEmpty {
                    Text("This athlete hasn't added contact details yet.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                } else {
                    if contact.guardianName != nil || contact.guardianEmail != nil || contact.guardianPhone != nil {
                        Text("Contact a minor's guardian first when one is listed.")
                            .font(.caption)
                            .foregroundStyle(Color.hubWarning)
                    }
                    contactRow("Guardian", contact.guardianName, nil)
                    contactRow("Guardian email", contact.guardianEmail, "mailto:")
                    contactRow("Guardian phone", contact.guardianPhone, "tel:")
                    contactRow("Athlete email", contact.athleteEmail, "mailto:")
                    contactRow("Athlete phone", contact.athletePhone, "tel:")
                    contactRow("Club coach", contact.clubCoachName, nil)
                    contactRow("Club coach phone", contact.clubCoachPhone, "tel:")
                }
            } else {
                Label {
                    Text("Save to Recruiting Board to unlock contact information")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(Color.hubTextSecondary)
                }
            }
        }
    }

    private var reportButton: some View {
        Button {
            showReport = true
        } label: {
            Label("Report this profile", systemImage: "flag")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func load() async {
        guard let programId else { unavailable = true; return }
        do {
            let fetched = try await CoachWorkspaceService.shared.detail(programId: programId, athleteId: athleteId)
            detail = fetched
            tags = fetched.board?.tags ?? []
            noteDraft = fetched.privateNote ?? ""
            noteSaved = false
            loadFailed = false
            unavailable = false
            if let entry = fetched.board, !entry.isRemoved {
                async let staffTask = CoachWorkspaceService.shared.staff(programId: programId)
                async let activityTask = CoachWorkspaceService.shared.boardActivity(programId: programId, entryId: entry.id, limit: 10)
                staff = (try? await staffTask) ?? []
                activity = (try? await activityTask) ?? []
            } else {
                activity = []
            }
        } catch {
            if let pg = error as? PostgrestError, pg.message == "not found" || pg.message == "not authorized" {
                unavailable = true
            } else {
                loadFailed = detail == nil
            }
        }
    }

    private func recordView() async {
        guard let programId, detail != nil else { return }
        try? await AthleteService.shared.recordProfileView(athleteId: athleteId, programId: programId)
    }

    private func save() async {
        guard let programId else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await CoachWorkspaceService.shared.saveToBoard(programId: programId, athleteId: athleteId)
            await load()   // picks up board state and the now-unlocked contact card
        } catch {
            errorMessage = "Couldn't save this athlete. \(error.localizedDescription)"
        }
    }

    private func setStage(_ entry: BoardEntry, _ stage: PipelineStage) async {
        guard stage != entry.stage else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await CoachWorkspaceService.shared.setStage(entryId: entry.id, stage: stage)
            detail?.board = updated
        } catch {
            errorMessage = "Couldn't change the stage."
        }
    }

    private func saveTags(_ entry: BoardEntry, _ cleaned: [String]) async {
        guard cleaned != entry.tags else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await CoachWorkspaceService.shared.setTags(entryId: entry.id, tags: cleaned)
            detail?.board = updated
            tags = updated.tags
        } catch {
            tags = entry.tags
            errorMessage = "Couldn't save tags. \(error.localizedDescription)"
        }
    }

    private func assign(_ entry: BoardEntry, _ user: String?) async {
        guard entry.assignedTo != user else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await CoachWorkspaceService.shared.assign(entryId: entry.id, to: user)
            detail?.board = updated
        } catch {
            errorMessage = "Couldn't update the assignment."
        }
    }

    private func saveNote() async {
        guard let userId else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let saved = try await CoachWorkspaceService.shared.savePrivateNote(coachUserId: userId, athleteId: athleteId, body: noteDraft)
            detail?.privateNote = saved?.body
            noteDraft = saved?.body ?? ""
            noteSaved = true
        } catch {
            errorMessage = "Couldn't save your note. \(error.localizedDescription)"
        }
    }

    private func remove() async {
        guard let entry = detail?.board else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await CoachWorkspaceService.shared.removeFromBoard(entryId: entry.id)
            await load()
        } catch {
            errorMessage = "Couldn't remove this athlete."
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Color.hubTextSecondary)
            Text(value ?? "—").font(.subheadline.bold()).foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func contactRow(_ label: String, _ value: String?, _ scheme: String?) -> some View {
        if let value, !value.isBlank {
            HStack {
                Text(label).font(.caption).foregroundStyle(Color.hubTextSecondary).frame(width: 120, alignment: .leading)
                if let scheme, let url = URL(string: scheme + value.filter { !$0.isWhitespace }) {
                    Link(value, destination: url).font(.subheadline).foregroundStyle(Color.hubPrimary)
                } else {
                    Text(value).font(.subheadline).foregroundStyle(.white).textSelection(.enabled)
                }
                Spacer()
            }
        }
    }

    private func platformLabel(for url: String) -> String {
        let lowered = url.lowercased()
        if lowered.contains("youtube.com") || lowered.contains("youtu.be") { return "YouTube" }
        if lowered.contains("hudl.com") { return "Hudl" }
        if lowered.contains("vimeo.com") { return "Vimeo" }
        if lowered.contains("tiktok.com") { return "TikTok" }
        if lowered.contains("instagram.com") { return "Instagram" }
        return "Video link"
    }
}
