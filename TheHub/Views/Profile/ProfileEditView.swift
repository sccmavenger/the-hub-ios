import SwiftUI
import Auth
import PhotosUI
import Kingfisher

struct ProfileEditView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = ProfileEditViewModel()
    @State private var videoToDelete: AthleteVideo?
    @State private var eventToDelete: AthleteEvent?

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
                }

                profilePhotoSection

                HubFormSection("Basic Info") {
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

                HubFormSection("Physical") {
                    HStack(spacing: 12) {
                        HubTextField(label: "Height (ft)", text: $viewModel.heightFeetText, keyboardType: .numberPad, maxLength: 1)
                        HubTextField(label: "Height (in)", text: $viewModel.heightInchesText, keyboardType: .numberPad, maxLength: 2)
                    }
                    HubTextField(label: "Weight (lbs)", text: $viewModel.weightText, keyboardType: .numberPad, maxLength: 3)
                }

                HubFormSection("Academics") {
                    HubTextField(label: "GPA", text: $viewModel.gpaText, keyboardType: .decimalPad, maxLength: 4)
                    HStack(spacing: 12) {
                        HubTextField(label: "SAT", text: $viewModel.satText, keyboardType: .numberPad, maxLength: 4)
                        HubTextField(label: "ACT", text: $viewModel.actText, keyboardType: .numberPad, maxLength: 2)
                    }
                    HubTextField(label: "Intended Major", text: $viewModel.intendedMajor, autocapitalization: .words, maxLength: 80)
                    HubTextField(label: "NCAA ID", text: $viewModel.ncaaId, keyboardType: .numberPad, maxLength: 12)
                }

                HubFormSection("Social") {
                    HubTextField(label: "Instagram Handle", text: $viewModel.instagramHandle)
                    HubTextField(label: "TikTok Handle", text: $viewModel.tiktokHandle)
                }

                HubFormSection("Bio") {
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

                HubFormSection("Contact Info") {
                    HubTextField(label: "Athlete Email", text: $viewModel.athleteEmail, keyboardType: .emailAddress, textContentType: .emailAddress)
                    HubTextField(label: "Athlete Phone", text: $viewModel.athletePhone, keyboardType: .phonePad, textContentType: .telephoneNumber)
                    HubTextField(label: "Guardian Name", text: $viewModel.guardianName, autocapitalization: .words)
                    HubTextField(label: "Guardian Email", text: $viewModel.guardianEmail, keyboardType: .emailAddress)
                    HubTextField(label: "Guardian Phone", text: $viewModel.guardianPhone, keyboardType: .phonePad)
                    HubTextField(label: "Club Coach Name", text: $viewModel.clubCoachName, autocapitalization: .words)
                    HubTextField(label: "Club Coach Phone", text: $viewModel.clubCoachPhone, keyboardType: .phonePad)
                }

                HubFormSection("Eligibility & Consent") {
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

                HubFormSection("Visibility") {
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
        HubFormSection("Profile Photo") {
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
        HubFormSection("Photo Gallery (\(viewModel.photos.count)/\(ProfileEditViewModel.galleryLimit))") {
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
        HubFormSection("Highlight Videos (\(viewModel.videos.count)/\(ProfileEditViewModel.videoLimit))") {
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
        HubFormSection("Game Schedule") {
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
struct HubFormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
