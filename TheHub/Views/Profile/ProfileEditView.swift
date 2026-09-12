import SwiftUI
import Auth
import PhotosUI
import Kingfisher

struct ProfileEditView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = ProfileEditViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.hubGold)
                } else if viewModel.athlete == nil, let message = viewModel.errorMessage {
                    loadErrorState(message)
                } else {
                    form
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
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
            .foregroundStyle(Color.hubGold)
        }
    }

    private var form: some View {
        @Bindable var viewModel = viewModel

        return ScrollView {
            VStack(spacing: 20) {
                profilePhotoSection

                HubFormSection("Basic Info") {
                    HubTextField(label: "Full Name", text: $viewModel.fullName, autocapitalization: .words)
                    HubTextField(label: "Position", text: $viewModel.position, autocapitalization: .words)
                    HubTextField(label: "Jersey Number", text: $viewModel.jerseyNumber, keyboardType: .numberPad)
                    genderPicker
                    HubTextField(label: "Graduation Year", text: $viewModel.gradYearText, keyboardType: .numberPad)
                    HubTextField(label: "High School", text: $viewModel.highSchool, autocapitalization: .words)
                    HubTextField(label: "Hometown", text: $viewModel.hometown, autocapitalization: .words)
                    HubTextField(label: "State", text: $viewModel.state, autocapitalization: .characters)
                    HubTextField(label: "ZIP Code", text: $viewModel.zipCode, keyboardType: .numberPad)
                    dateOfBirthPicker
                }

                HubFormSection("Physical") {
                    HStack(spacing: 12) {
                        HubTextField(label: "Height (ft)", text: $viewModel.heightFeetText, keyboardType: .numberPad)
                        HubTextField(label: "Height (in)", text: $viewModel.heightInchesText, keyboardType: .numberPad)
                    }
                    HubTextField(label: "Weight (lbs)", text: $viewModel.weightText, keyboardType: .numberPad)
                }

                HubFormSection("Academics") {
                    HubTextField(label: "GPA", text: $viewModel.gpaText, keyboardType: .decimalPad)
                    HStack(spacing: 12) {
                        HubTextField(label: "SAT", text: $viewModel.satText, keyboardType: .numberPad)
                        HubTextField(label: "ACT", text: $viewModel.actText, keyboardType: .numberPad)
                    }
                    HubTextField(label: "Intended Major", text: $viewModel.intendedMajor, autocapitalization: .words)
                    HubTextField(label: "NCAA ID", text: $viewModel.ncaaId, keyboardType: .numberPad)
                }

                HubFormSection("Social") {
                    HubTextField(label: "Instagram Handle", text: $viewModel.instagramHandle)
                    HubTextField(label: "TikTok Handle", text: $viewModel.tiktokHandle)
                }

                HubFormSection("Bio") {
                    bioEditor
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
                    .tint(Color.hubGold)
                }

                if let message = viewModel.errorMessage {
                    HubErrorText(message: message)
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
        .alert("Profile Saved", isPresented: $viewModel.didSave) {
            Button("OK") {}
        }
    }

    // MARK: - Profile photo

    @State private var profilePhotoItem: PhotosPickerItem?

    private var profilePhotoSection: some View {
        HubFormSection("Profile Photo") {
            HStack(spacing: 16) {
                KFImage(URL(string: viewModel.athlete?.profilePhotoUrl ?? ""))
                    .placeholder {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())

                PhotosPicker(selection: $profilePhotoItem, matching: .images) {
                    if viewModel.isUploadingProfilePhoto {
                        ProgressView()
                            .tint(Color.hubGold)
                    } else {
                        Text("Change Photo")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.hubGold)
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
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await viewModel.uploadProfilePhoto(imageData: data)
                }
            }
        }
    }

    // MARK: - Gallery

    @State private var galleryPhotoItem: PhotosPickerItem?

    private var gallerySection: some View {
        HubFormSection("Photo Gallery (\(viewModel.photos.count)/\(ProfileEditViewModel.galleryLimit))") {
            if !viewModel.photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(viewModel.photos) { photo in
                        galleryThumbnail(photo)
                    }
                }
            }

            PhotosPicker(selection: $galleryPhotoItem, matching: .images) {
                if viewModel.isUploadingGalleryPhoto {
                    ProgressView()
                        .tint(Color.hubGold)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Add Photo", systemImage: "plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(viewModel.canAddGalleryPhoto ? Color.hubGold : Color.hubTextSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!viewModel.canAddGalleryPhoto || viewModel.isUploadingGalleryPhoto)
        }
        .onChange(of: galleryPhotoItem) {
            guard let item = galleryPhotoItem else { return }
            galleryPhotoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await viewModel.addGalleryPhoto(imageData: data)
                }
            }
        }
    }

    private func galleryThumbnail(_ photo: AthletePhoto) -> some View {
        KFImage(URL(string: photo.url))
            .placeholder {
                Rectangle()
                    .fill(Color.hubSurfaceElevated)
                    .overlay {
                        ProgressView()
                            .tint(Color.hubTextSecondary)
                    }
            }
            .resizable()
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fill)
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
    }

    // MARK: - Videos

    @State private var newVideoUrl = ""
    @State private var newVideoTitle = ""

    private var videosSection: some View {
        HubFormSection("Highlight Videos") {
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
                        Task { await viewModel.deleteVideo(video) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.hubError)
                    }
                    .accessibilityLabel("Delete video")
                }
                .padding(.vertical, 4)
            }

            HubTextField(label: "Video URL", text: $newVideoUrl, keyboardType: .URL)
            HubTextField(label: "Title (optional)", text: $newVideoTitle, autocapitalization: .words)

            Button {
                let url = newVideoUrl
                let title = newVideoTitle
                newVideoUrl = ""
                newVideoTitle = ""
                Task { await viewModel.addVideo(url: url, title: title) }
            } label: {
                Label("Add Video", systemImage: "plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.hubGold)
            .disabled(newVideoUrl.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Schedule

    @State private var newEventDate = Date()
    @State private var newEventTime = ""
    @State private var newEventOpponent = ""
    @State private var newEventLocation = ""
    @State private var newEventIsMaybe = false

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
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.hubGold)
                                    .clipShape(Capsule())
                            }
                        }
                        Text([event.opponent, event.location].compactMap(\.self).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                    Spacer()
                    Button {
                        Task { await viewModel.deleteEvent(event) }
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
                .tint(Color.hubGold)

            HubTextField(label: "Time (optional)", text: $newEventTime)
            HubTextField(label: "Opponent", text: $newEventOpponent, autocapitalization: .words)
            HubTextField(label: "Location", text: $newEventLocation, autocapitalization: .words)

            Toggle("MAYB Event", isOn: $newEventIsMaybe)
                .foregroundStyle(.white)
                .tint(Color.hubGold)

            Button {
                let date = newEventDate
                let time = newEventTime
                let opponent = newEventOpponent
                let location = newEventLocation
                let isMaybe = newEventIsMaybe
                newEventTime = ""
                newEventOpponent = ""
                newEventLocation = ""
                newEventIsMaybe = false
                Task {
                    await viewModel.addEvent(
                        date: date,
                        time: time,
                        opponent: opponent,
                        location: location,
                        notes: "",
                        isMaybe: isMaybe
                    )
                }
            } label: {
                Label("Add Game", systemImage: "plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.hubGold)
        }
    }

    // MARK: - Small pieces

    private var genderPicker: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 6) {
            Text("Sport")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            Picker("Sport", selection: $viewModel.sportGender) {
                ForEach(SportGender.allCases, id: \.self) { gender in
                    Text(gender.displayName).tag(gender)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var dateOfBirthPicker: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 6) {
            Toggle("Date of Birth", isOn: $viewModel.hasDateOfBirth)
                .foregroundStyle(.white)
                .tint(Color.hubGold)

            if viewModel.hasDateOfBirth {
                DatePicker("", selection: $viewModel.dateOfBirth, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color.hubGold)
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
                .foregroundStyle(Color.hubGold)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
