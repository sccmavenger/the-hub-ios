import SwiftUI
import Auth
import PhotosUI
import Kingfisher
import UniformTypeIdentifiers

struct ProfileEditView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = ProfileEditViewModel()
    @State private var videoToDelete: AthleteVideo?
    @State private var eventToDelete: AthleteEvent?

    // MARK: - Collapsible sections (TestFlight feedback 2026-09-30)

    /// Each card collapses to a header with an "x of y" completion chip so the
    /// long form reads as a checklist. Create mode opens everything; edit mode
    /// starts collapsed.
    private enum SectionKey: CaseIterable {
        case photo, basic, physical, academics, social, bio, gallery, videos, schedule, contact, consent, visibility
    }

    @State private var expandedSections: Set<SectionKey> = []
    @State private var sectionsPrimed = false

    private func expansion(_ key: SectionKey) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(key) },
            set: { open in if open { expandedSections.insert(key) } else { expandedSections.remove(key) } }
        )
    }

    private func filled(_ values: String...) -> Int {
        values.filter { !$0.isBlank }.count
    }

    private func completion(_ key: SectionKey) -> (done: Int, total: Int) {
        switch key {
        case .photo:
            return ((viewModel.athlete?.hasProfilePhoto ?? false) ? 1 : 0, 1)
        case .basic:
            return (filled(viewModel.fullName, viewModel.position, viewModel.jerseyNumber, viewModel.gradYearText,
                           viewModel.highSchool, viewModel.hometown, viewModel.state, viewModel.zipCode)
                    + (viewModel.hasDateOfBirth ? 1 : 0), 9)
        case .physical:
            return (((viewModel.heightFeetText + viewModel.heightInchesText).isBlank ? 0 : 1) + filled(viewModel.weightText), 2)
        case .academics:
            return (filled(viewModel.gpaText, viewModel.satText, viewModel.actText, viewModel.intendedMajor, viewModel.ncaaId), 5)
        case .social:
            return (filled(viewModel.instagramHandle, viewModel.tiktokHandle), 2)
        case .bio:
            return (filled(viewModel.bio), 1)
        case .gallery:
            return (viewModel.photos.isEmpty ? 0 : 1, 1)
        case .videos:
            return (viewModel.videos.isEmpty ? 0 : 1, 1)
        case .schedule:
            return (viewModel.events.isEmpty ? 0 : 1, 1)
        case .contact:
            let shared = filled(viewModel.athleteEmail, viewModel.guardianName, viewModel.guardianEmail,
                                viewModel.guardianPhone, viewModel.clubCoachName, viewModel.clubCoachPhone)
            return viewModel.isAthleteAdult ? (shared + filled(viewModel.athletePhone), 7) : (shared, 6)
        case .consent:
            return (filled(viewModel.consentName, viewModel.consentEmail), 2)
        case .visibility:
            return (viewModel.isPublished ? 1 : 0, 1)
        }
    }

    private var completedSectionCount: Int {
        SectionKey.allCases.filter { completion($0).done >= completion($0).total }.count
    }

    // MARK: - Schedule import (.ics)

    private struct ICSCandidates: Identifiable {
        let id = UUID()
        let events: [ICSParser.Event]
    }

    @State private var showICSImporter = false
    @State private var icsCandidates: ICSCandidates?
    @State private var icsError: String?

    private static let icsTypes: [UTType] = [UTType(filenameExtension: "ics") ?? .data, .calendarEvent]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.hubPrimary)
                } else if viewModel.loadFailed, let message = viewModel.errorMessage {
                    loadErrorState(message)
                } else {
                    form
                }
            }
            .navigationTitle(viewModel.isCreateMode ? "Create Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.managedAthletes.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(viewModel.managedAthletes) { athlete in
                                Button {
                                    Task { await viewModel.select(athleteId: athlete.id) }
                                } label: {
                                    if athlete.id == viewModel.athlete?.id {
                                        Label(athlete.fullName, systemImage: "checkmark")
                                    } else {
                                        Text(athlete.fullName)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "person.2.circle")
                                .foregroundStyle(Color.hubPrimary)
                        }
                        .accessibilityLabel("Switch athlete")
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let userId = authViewModel.session?.user.id.uuidString else { return }
        await viewModel.load(userId: userId)
    }

    private func loadErrorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubWarning)
            Text("Couldn't load your profile")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await load() }
            }
            .foregroundStyle(Color.hubPrimary)
        }
    }

    private var form: some View {
        @Bindable var viewModel = viewModel

        return ScrollView {
            VStack(spacing: 20) {
                if viewModel.isCreateMode {
                    Text("Create your athlete profile — fill in the basics and hit Save. You can add photos, videos and your schedule right after.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    HStack(spacing: 10) {
                        Text("\(completedSectionCount) of \(SectionKey.allCases.count) sections complete")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Spacer()
                        Button(expandedSections.isEmpty ? "Expand all" : "Collapse all") {
                            withAnimation(.snappy) {
                                expandedSections = expandedSections.isEmpty ? Set(SectionKey.allCases) : []
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color.hubPrimary)
                    }
                    .padding(.top, 8)
                }

                profilePhotoSection

                HubFormSection("Basic Info", completion: completion(.basic), isExpanded: expansion(.basic)) {
                    HubTextField(label: "Full Name", text: $viewModel.fullName, autocapitalization: .words)
                    HubTextField(label: "Position", text: $viewModel.position, autocapitalization: .words)
                    HubTextField(label: "Jersey Number", text: $viewModel.jerseyNumber, keyboardType: .numberPad, maxLength: 2)
                    genderPicker
                    HubTextField(label: "Graduation Year", text: $viewModel.gradYearText, keyboardType: .numberPad, maxLength: 4)
                    HubTextField(label: "High School", text: $viewModel.highSchool, autocapitalization: .words)
                    HubTextField(label: "Hometown", text: $viewModel.hometown, autocapitalization: .words)
                    HubTextField(label: "State", text: $viewModel.state, autocapitalization: .characters)
                    HubTextField(label: "ZIP Code", text: $viewModel.zipCode, keyboardType: .numberPad)
                    dateOfBirthPicker
                }

                HubFormSection("Physical", completion: completion(.physical), isExpanded: expansion(.physical)) {
                    HStack(spacing: 12) {
                        HubTextField(label: "Height (ft)", text: $viewModel.heightFeetText, keyboardType: .numberPad, maxLength: 1)
                        HubTextField(label: "Height (in)", text: $viewModel.heightInchesText, keyboardType: .numberPad, maxLength: 2)
                    }
                    HubTextField(label: "Weight (lbs)", text: $viewModel.weightText, keyboardType: .numberPad, maxLength: 3)
                }

                HubFormSection("Academics", completion: completion(.academics), isExpanded: expansion(.academics)) {
                    HubTextField(label: "GPA", text: $viewModel.gpaText, keyboardType: .decimalPad, maxLength: 4)
                    HStack(spacing: 12) {
                        HubTextField(label: "SAT", text: $viewModel.satText, keyboardType: .numberPad, maxLength: 4)
                        HubTextField(label: "ACT", text: $viewModel.actText, keyboardType: .numberPad, maxLength: 2)
                    }
                    HubTextField(label: "Intended Major", text: $viewModel.intendedMajor, autocapitalization: .words, maxLength: 80)
                    HubTextField(label: "NCAA ID", text: $viewModel.ncaaId, keyboardType: .numberPad, maxLength: 12)
                }

                HubFormSection("Social", completion: completion(.social), isExpanded: expansion(.social)) {
                    HubTextField(label: "Instagram Handle", text: $viewModel.instagramHandle)
                    HubTextField(label: "TikTok Handle", text: $viewModel.tiktokHandle)
                }

                HubFormSection("Bio", completion: completion(.bio), isExpanded: expansion(.bio)) {
                    bioEditor
                        .onChange(of: viewModel.bio) {
                            // Hard-stop at the limit instead of letting the
                            // user keep typing into a save that will fail
                            if viewModel.bio.count > ProfileEditViewModel.bioLimit {
                                viewModel.bio = String(viewModel.bio.prefix(ProfileEditViewModel.bioLimit))
                            }
                        }
                    Text("\(viewModel.bio.count)/\(ProfileEditViewModel.bioLimit)")
                        .font(.caption2)
                        .foregroundStyle(
                            viewModel.bio.count > ProfileEditViewModel.bioLimit
                                ? Color.hubError : Color.hubTextSecondary
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                gallerySection
                videosSection
                scheduleSection

                HubFormSection("Contact Info", completion: completion(.contact), isExpanded: expansion(.contact)) {
                    // 021: a minor's own email/phone are never shown to coaches, and
                    // the phone isn't collected at all. Adults (18+ by date of birth)
                    // can share both.
                    Text(viewModel.isAthleteAdult
                         ? "Coaches who save you to their board can see these details."
                         : "Coaches never see an athlete's own email or phone while they're under 18. They reach the family through the guardian or club coach listed here, or by messaging in The Hub.")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)

                    HubTextField(label: "Athlete Email", text: $viewModel.athleteEmail, keyboardType: .emailAddress, textContentType: .emailAddress)
                    if viewModel.isAthleteAdult {
                        HubTextField(label: "Athlete Phone", text: $viewModel.athletePhone, keyboardType: .phonePad, textContentType: .telephoneNumber)
                    }
                    HubTextField(label: "Guardian Name", text: $viewModel.guardianName, autocapitalization: .words)
                    HubTextField(label: "Guardian Email", text: $viewModel.guardianEmail, keyboardType: .emailAddress)
                    HubTextField(label: "Guardian Phone", text: $viewModel.guardianPhone, keyboardType: .phonePad)
                    HubTextField(label: "Club Coach Name", text: $viewModel.clubCoachName, autocapitalization: .words)
                    HubTextField(label: "Club Coach Phone", text: $viewModel.clubCoachPhone, keyboardType: .phonePad)
                }

                HubFormSection("Eligibility & Consent", completion: completion(.consent), isExpanded: expansion(.consent)) {
                    Text("A parent or guardian must consent before a minor's profile can be published. Their name and email are recorded with the consent date.")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)

                    HubTextField(label: "Parent/Guardian Name", text: $viewModel.consentName, autocapitalization: .words)
                    HubTextField(label: "Parent/Guardian Email", text: $viewModel.consentEmail, keyboardType: .emailAddress)

                    if let recorded = viewModel.consentRecordedAt {
                        Label("Consent recorded \(recorded.asFormattedDate())", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Color.hubSuccess)
                    }
                }

                HubFormSection("Visibility", completion: completion(.visibility), isExpanded: expansion(.visibility)) {
                    Toggle(isOn: $viewModel.isPublished) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Publish Profile")
                                .foregroundStyle(.white)
                            Text("Published profiles are visible to college coaches.")
                                .font(.caption)
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                    }
                    .tint(Color.hubPrimary)
                }

                if let message = viewModel.errorMessage {
                    HubErrorText(message: message)
                }
                if let info = viewModel.infoMessage {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(Color.hubWarning)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                HubPrimaryButton("Save Profile", isLoading: viewModel.isSaving) {
                    Task { await viewModel.save() }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.success, trigger: viewModel.didSave)
        .onAppear {
            guard !sectionsPrimed else { return }
            sectionsPrimed = true
            if viewModel.isCreateMode { expandedSections = Set(SectionKey.allCases) }
        }
        .fileImporter(isPresented: $showICSImporter, allowedContentTypes: Self.icsTypes) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
                    icsCandidates = ICSCandidates(events: ICSParser.parse(text))
                    icsError = nil
                } else {
                    icsError = "Couldn't read that file. Export the schedule as an .ics calendar file and try again."
                }
            case .failure:
                icsError = "Couldn't open that file."
            }
        }
        .sheet(item: $icsCandidates) { candidates in
            ICSImportSheet(events: candidates.events, existing: viewModel.events) { chosen in
                await viewModel.importEvents(chosen)
            }
        }
        .confirmationDialog(
            "Delete this video?",
            isPresented: .init(
                get: { videoToDelete != nil },
                set: { if !$0 { videoToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let video = videoToDelete {
                    Task { await viewModel.deleteVideo(video) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this game?",
            isPresented: .init(
                get: { eventToDelete != nil },
                set: { if !$0 { eventToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let event = eventToDelete {
                    Task { await viewModel.deleteEvent(event) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Profile Saved", isPresented: $viewModel.didSave) {
            Button("OK") {}
        } message: {
            // Surface the ZIP/geocode warning here — at the bottom of a long
            // form it scrolled off-screen and was effectively invisible.
            if let info = viewModel.infoMessage {
                Text(info)
            }
        }
    }

    // MARK: - Profile photo

    @State private var profilePhotoItem: PhotosPickerItem?
    @State private var photoToCrop: CropCandidate?

    private var profilePhotoSection: some View {
        HubFormSection("Profile Photo", completion: completion(.photo), isExpanded: expansion(.photo)) {
            HStack(spacing: 16) {
                HubRemoteImage(path: viewModel.athlete?.profilePhotoPath, legacyURL: viewModel.athlete?.profilePhotoUrl) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.hubTextSecondary)
                }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())

                PhotosPicker(selection: $profilePhotoItem, matching: .images) {
                    if viewModel.isUploadingProfilePhoto {
                        ProgressView()
                            .tint(Color.hubPrimary)
                    } else {
                        Text("Change Photo")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.hubPrimary)
                    }
                }
                .disabled(viewModel.isUploadingProfilePhoto)

                Spacer()
            }
        }
        .onChange(of: profilePhotoItem) {
            guard let item = profilePhotoItem else { return }
            profilePhotoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = PhotoCropperView.downsampledImage(data: data, maxDimension: 2400) {
                    photoToCrop = CropCandidate(image: image)
                }
            }
        }
        .sheet(item: $photoToCrop) { candidate in
            PhotoCropperView(image: candidate.image) { jpegData in
                Task { await viewModel.uploadProfilePhoto(imageData: jpegData) }
            }
        }
    }

    // MARK: - Gallery

    @State private var galleryPhotoItems: [PhotosPickerItem] = []

    private var gallerySection: some View {
        HubFormSection("Photo Gallery (\(viewModel.photos.count)/\(ProfileEditViewModel.galleryLimit))", completion: completion(.gallery), isExpanded: expansion(.gallery)) {
            if !viewModel.photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(viewModel.photos) { photo in
                        galleryThumbnail(photo)
                    }
                }
            }

            PhotosPicker(
                selection: $galleryPhotoItems,
                maxSelectionCount: max(ProfileEditViewModel.galleryLimit - viewModel.photos.count, 0),
                matching: .images
            ) {
                if let progress = viewModel.galleryUploadProgress {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.hubPrimary)
                        Text("Uploading \(min(progress.completed + 1, progress.total)) of \(progress.total)…")
                            .font(.subheadline)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                } else if viewModel.isUploadingGalleryPhoto {
                    ProgressView()
                        .tint(Color.hubPrimary)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Add Photos", systemImage: "plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(viewModel.canAddGalleryPhoto ? Color.hubPrimary : Color.hubTextSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!viewModel.canAddGalleryPhoto || viewModel.isUploadingGalleryPhoto)
        }
        .onChange(of: galleryPhotoItems) {
            let items = galleryPhotoItems
            guard !items.isEmpty else { return }
            galleryPhotoItems = []
            Task {
                var payloads: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        payloads.append(data)
                    }
                }
                await viewModel.addGalleryPhotos(payloads)
            }
        }
    }

    private func galleryThumbnail(_ photo: AthletePhoto) -> some View {
        GalleryTile(photo: photo, viewModel: viewModel)
    }

    // MARK: - Videos

    @State private var newVideoUrl = ""
    @State private var newVideoTitle = ""

    private var videosSection: some View {
        HubFormSection("Highlight Videos (\(viewModel.videos.count)/\(ProfileEditViewModel.videoLimit))", completion: completion(.videos), isExpanded: expansion(.videos)) {
            ForEach(viewModel.videos) { video in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title ?? "Untitled Video")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Text(video.url)
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        videoToDelete = video
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.hubError)
                    }
                    .accessibilityLabel("Delete video")
                }
                .padding(.vertical, 4)
            }

            HubTextField(label: "Video URL", text: $newVideoUrl, keyboardType: .URL)
                .onChange(of: newVideoUrl) { viewModel.videoError = nil }
            HubTextField(label: "Title (optional)", text: $newVideoTitle, autocapitalization: .words, maxLength: 80)

            if let videoError = viewModel.videoError {
                HubErrorText(message: videoError)
            }

            Button {
                let url = newVideoUrl
                let title = newVideoTitle
                Task {
                    // Only clear the fields when it actually saved, so a
                    // rejected URL stays on screen next to the error
                    if await viewModel.addVideo(url: url, title: title) {
                        newVideoUrl = ""
                        newVideoTitle = ""
                    }
                }
            } label: {
                Label("Add Video", systemImage: "plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.hubPrimary)
            .disabled(newVideoUrl.trimmingCharacters(in: .whitespaces).isEmpty || !viewModel.canAddVideo)

            if !viewModel.canAddVideo {
                Text("You've reached the limit of \(ProfileEditViewModel.videoLimit) videos. Remove one to add another.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        }
    }

    // MARK: - Schedule

    @State private var newEventDate = Date()
    @State private var newEventTime = ""
    @State private var newEventOpponent = ""
    @State private var newEventLocation = ""

    private var scheduleSection: some View {
        HubFormSection("Game Schedule", completion: completion(.schedule), isExpanded: expansion(.schedule)) {
            // Bulk import from the team's published calendar (TestFlight feedback 2026-09-30).
            Button {
                showICSImporter = true
            } label: {
                Label("Import from a calendar file (.ics)", systemImage: "calendar.badge.plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.hubPrimary)
            Text("Most school and club sites offer a schedule download or \"Add to calendar\" link that saves an .ics file. Open it here to add every game at once.")
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)
            if let icsError {
                HubErrorText(message: icsError)
            }

            ForEach(viewModel.events) { event in
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
                        Text([event.opponent, event.location].compactMap(\.self).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                    Spacer()
                    Button {
                        eventToDelete = event
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.hubError)
                    }
                    .accessibilityLabel("Delete event")
                }
                .padding(.vertical, 4)
            }

            DatePicker("Date", selection: $newEventDate, displayedComponents: .date)
                .foregroundStyle(.white)
                .tint(Color.hubPrimary)

            HubTextField(label: "Time (optional)", text: $newEventTime, maxLength: 20)
            HubTextField(label: "Opponent", text: $newEventOpponent, autocapitalization: .words, maxLength: 60)
            HubTextField(label: "Location", text: $newEventLocation, autocapitalization: .words, maxLength: 80)

            if let eventError = viewModel.eventError {
                HubErrorText(message: eventError)
            }

            Button {
                let date = newEventDate
                let time = newEventTime
                let opponent = newEventOpponent
                let location = newEventLocation
                Task {
                    if await viewModel.addEvent(
                        date: date,
                        time: time,
                        opponent: opponent,
                        location: location,
                        notes: "",
                        isMaybe: false
                    ) {
                        newEventTime = ""
                        newEventOpponent = ""
                        newEventLocation = ""
                    }
                }
            } label: {
                Label("Add Game", systemImage: "plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.hubPrimary)
        }
    }

    // MARK: - Small pieces

    private var genderPicker: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 6) {
            Text("Basketball")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            Picker("Basketball", selection: $viewModel.sportGender) {
                ForEach(SportGender.allCases, id: \.self) { gender in
                    Text(gender.basketballLabel).tag(gender)
                }
            }
            .pickerStyle(.segmented)

            Text("Sets which NCAA recruiting calendar applies — men's and women's basketball have different contact rules.")
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)
        }
    }

    private var dateOfBirthPicker: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 6) {
            Toggle("Date of Birth", isOn: $viewModel.hasDateOfBirth)
                .foregroundStyle(.white)
                .tint(Color.hubPrimary)

            if viewModel.hasDateOfBirth {
                DatePicker("", selection: $viewModel.dateOfBirth, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color.hubPrimary)
            }
        }
    }

    private var bioEditor: some View {
        @Bindable var viewModel = viewModel

        return TextEditor(text: $viewModel.bio)
            .frame(minHeight: 120)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(Color.hubSurface)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.hubBorder, lineWidth: 1)
            )
    }
}

/// Gallery photo tile with delete overlay and an editable caption (120 max).
private struct GalleryTile: View {
    let photo: AthletePhoto
    let viewModel: ProfileEditViewModel
    @State private var caption: String
    @FocusState private var captionFocused: Bool

    init(photo: AthletePhoto, viewModel: ProfileEditViewModel) {
        self.photo = photo
        self.viewModel = viewModel
        _caption = State(initialValue: photo.caption ?? "")
    }

    var body: some View {
        VStack(spacing: 6) {
            // Square cell first, image filled and clipped inside it — scaledToFill
            // with no fixed frame lets tall photos paint over the whole screen.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    HubRemoteImage(path: photo.storagePath, legacyURL: photo.url) {
                        Rectangle()
                            .fill(Color.hubSurfaceElevated)
                            .overlay {
                                ProgressView()
                                    .tint(Color.hubTextSecondary)
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    Button {
                        Task { await viewModel.deletePhoto(photo) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.hubError)
                    }
                    .padding(4)
                    .accessibilityLabel("Delete photo")
                }

            TextField("Caption", text: $caption)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.hubSurface)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: caption) {
                    caption = String(caption.prefix(120))
                }
                .onSubmit {
                    Task { await viewModel.updateCaption(for: photo, caption: caption) }
                }
                // Captions were lost when the user tapped away instead of
                // pressing Return — save on focus loss too.
                .focused($captionFocused)
                .onChange(of: captionFocused) { _, focused in
                    if !focused, caption != (photo.caption ?? "") {
                        Task { await viewModel.updateCaption(for: photo, caption: caption) }
                    }
                }
        }
    }
}

/// Titled card wrapping a group of form fields, matching the dark theme.
/// Optionally shows an "x of y" completion chip and collapses to its header
/// when given an expansion binding.
struct HubFormSection<Content: View>: View {
    let title: String
    var completion: (done: Int, total: Int)?
    var isExpanded: Binding<Bool>?
    @ViewBuilder let content: Content

    init(
        _ title: String,
        completion: (done: Int, total: Int)? = nil,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.completion = completion
        self.isExpanded = isExpanded
        self.content = content()
    }

    private var showsContent: Bool { isExpanded?.wrappedValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let isExpanded {
                Button {
                    withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
                } label: {
                    headerRow(collapsible: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(showsContent ? "expanded" : "collapsed")")
                .accessibilityHint(showsContent ? "Collapses the section" : "Expands the section")
            } else {
                headerRow(collapsible: false)
            }

            if showsContent {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func headerRow(collapsible: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)
            Spacer(minLength: 8)
            if let completion {
                let complete = completion.done >= completion.total
                Text("\(completion.done) of \(completion.total)")
                    .font(.caption.bold())
                    .foregroundStyle(complete ? Color.hubSuccess : Color.hubTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((complete ? Color.hubSuccess : Color.hubTextSecondary).opacity(0.15))
                    .clipShape(Capsule())
            }
            if collapsible {
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubTextSecondary)
                    .rotationEffect(.degrees(showsContent ? 0 : -90))
            }
        }
        .contentShape(Rectangle())
    }
}
