import SwiftUI
import Kingfisher

/// Read-only athlete profile, modeled on the web app's public /a/:athleteId
/// page. Used today as the athlete's own "preview what coaches see"; the
/// coach-facing detail view in Phase 4 will build on it.
struct PublicProfileView: View {
    let athlete: Athlete

    @State private var photos: [AthletePhoto] = []
    @State private var videos: [AthleteVideo] = []
    @State private var events: [AthleteEvent] = []
    @State private var contact: AthleteContact?

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if !athlete.isPublished {
                        unpublishedBanner
                    }
                    header
                    if let bio = athlete.bio, !bio.isBlank {
                        sectionCard("About") {
                            Text(bio)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                    }
                    academicsCard
                    if !photos.isEmpty { photosSection }
                    if !videos.isEmpty { videosSection }
                    if !events.isEmpty { scheduleSection }
                    contactCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Profile Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Share = a rendered image of the public header + a line of text.
                // There is no public profile URL to share (profiles are visible
                // only to approved coaches), so nothing private can leak.
                if let shareImage {
                    ShareLink(
                        item: Image(uiImage: shareImage),
                        subject: Text("\(athlete.fullName) — The Hub"),
                        message: Text(ProfileShare.message(for: athlete)),
                        preview: SharePreview("\(athlete.fullName) · The Hub", image: Image(uiImage: shareImage))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share profile")
                } else {
                    ProgressView().tint(Color.hubPrimary).controlSize(.small)
                }
            }
        }
        .task { await load() }
        .task(id: athlete.id) {
            let photo = await ProfileShare.photo(for: athlete)
            shareImage = ProfileShare.render(athlete: athlete, photo: photo)
        }
    }

    @State private var shareImage: UIImage?

    private func load() async {
        async let photos = AthleteService.shared.fetchPhotos(athleteId: athlete.id)
        async let videos = AthleteService.shared.fetchVideos(athleteId: athlete.id)
        async let events = AthleteService.shared.fetchEvents(athleteId: athlete.id)
        async let contact = AthleteService.shared.fetchContact(athleteId: athlete.id)
        self.photos = (try? await photos) ?? []
        self.videos = (try? await videos) ?? []
        self.events = (try? await events) ?? []
        self.contact = try? await contact
    }

    // MARK: - Sections

    private var unpublishedBanner: some View {
        Label("This profile isn't published yet — coaches can't see it. Flip the publish toggle in Edit Profile when you're ready.", systemImage: "eye.slash")
            .font(.caption)
            .foregroundStyle(Color.hubWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.hubWarning.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HubRemoteImage(path: athlete.profilePhotoPath, legacyURL: athlete.profilePhotoUrl) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Color.hubTextSecondary)
            }
                .frame(width: 88, height: 88)
                .clipShape(Circle())

            Text(athlete.fullName)
                .font(.title2.bold())
                .foregroundStyle(.white)

            let schoolLine = [
                athlete.highSchool,
                [athlete.hometown, athlete.state].compactMap(\.self).joined(separator: ", ")
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
            if !schoolLine.isEmpty {
                Text(schoolLine)
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            }

            let chips: [String] = [
                athlete.position,
                athlete.gradYear.map { "Class of \($0)" },
                athlete.heightDisplay,
                athlete.weightLbs.map { "\($0) lbs" },
                athlete.jerseyNumber.map { "#\($0)" }
            ].compactMap(\.self)

            if !chips.isEmpty {
                FlowChips(chips: chips)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var academicsCard: some View {
        sectionCard("Academics") {
            HStack(spacing: 0) {
                academicStat("GPA", athlete.gpa.map { String($0) })
                academicStat("SAT", athlete.satScore.map(String.init))
                academicStat("ACT", athlete.actScore.map(String.init))
            }
            if let major = athlete.intendedMajor, !major.isBlank {
                Text("Intended major: \(major)")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        }
    }

    private func academicStat(_ label: String, _ value: String?) -> some View {
        VStack(spacing: 4) {
            Text(value ?? "—")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    @State private var photoViewer: PhotoViewerContext?

    private var photosSection: some View {
        sectionCard("Action Photos") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        photoViewer = PhotoViewerContext(index: index)
                    } label: {
                        // Square cell first, image filled and clipped inside it —
                        // scaledToFill with no fixed frame paints over neighboring cells.
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                HubRemoteImage(path: photo.storagePath, legacyURL: photo.url) {
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
        .fullScreenCover(item: $photoViewer) { context in
            PhotoViewer(photos: photos, initialIndex: context.index)
        }
    }

    private var videosSection: some View {
        sectionCard("Highlight Videos") {
            ForEach(videos) { video in
                if let url = URL(string: video.url) {
                    Link(destination: url) {
                        HStack(spacing: 10) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.hubPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.title ?? "Highlight Video")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Text(platformLabel(for: video.url))
                                    .font(.caption)
                                    .foregroundStyle(Color.hubTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        sectionCard("Upcoming Schedule") {
            ForEach(events) { event in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(event.eventDate.asFormattedDate())
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            if event.isMaybe {
                                Text("MAYB")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.hubPrimary)
                                    .clipShape(Capsule())
                            }
                        }
                        let detail = [event.eventTime, event.opponent.map { "vs \($0)" }, event.location]
                            .compactMap(\.self)
                            .joined(separator: " • ")
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var contactCard: some View {
        sectionCard("Contact Info") {
            Text("Visible only to approved college coaches who saved this profile.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)

            if let contact, hasAnyContact(contact) {
                contactRow("Athlete email", contact.athleteEmail)
                contactRow("Athlete phone", contact.athletePhone)
                contactRow("Guardian", contact.guardianName)
                contactRow("Guardian email", contact.guardianEmail)
                contactRow("Guardian phone", contact.guardianPhone)
                contactRow("Club coach", contact.clubCoachName)
                contactRow("Club coach phone", contact.clubCoachPhone)
            } else {
                Text("No contact details added yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        }
    }

    @ViewBuilder
    private func contactRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isBlank {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .layoutPriority(0)
                Spacer(minLength: 12)
                // No hyphenation: a wrapped email was rendering as
                // "…summithoops.exam-/ple", i.e. a hyphen that isn't part of
                // the address a coach would copy.
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .layoutPriority(1)
            }
        }
    }

    private func hasAnyContact(_ contact: AthleteContact) -> Bool {
        [contact.athleteEmail, contact.athletePhone, contact.guardianName,
         contact.guardianEmail, contact.guardianPhone,
         contact.clubCoachName, contact.clubCoachPhone]
            .contains { !($0 ?? "").isBlank }
    }

    // MARK: - Helpers

    private func sectionCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
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

/// Identifies which photo the fullscreen viewer opens on.
private struct PhotoViewerContext: Identifiable {
    let id = UUID()
    let index: Int
}

/// Fullscreen photo pager — swipe horizontally between gallery photos.
private struct PhotoViewer: View {
    let photos: [AthletePhoto]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(photos: [AthletePhoto], initialIndex: Int) {
        self.photos = photos
        _index = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                    VStack(spacing: 12) {
                        HubRemoteImage(path: photo.storagePath, legacyURL: photo.url, contentMode: .fit) {
                            ProgressView()
                                .tint(Color.hubTextSecondary)
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let caption = photo.caption, !caption.isBlank {
                            Text(caption)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 32)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, Color.hubSurfaceElevated)
            }
            .padding()
            .accessibilityLabel("Close photo viewer")
        }
    }
}

/// Simple wrapping chip row for profile tags.
private struct FlowChips: View {
    let chips: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.hubSurfaceElevated)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }
}
