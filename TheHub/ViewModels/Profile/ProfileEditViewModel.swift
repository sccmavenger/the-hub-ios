import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ProfileEditViewModel {
    private(set) var athlete: Athlete?
    var managedAthletes: [Athlete] = []
    var photos: [AthletePhoto] = []
    var videos: [AthleteVideo] = []
    var events: [AthleteEvent] = []

    // Basic
    var fullName = ""
    var position = ""
    var jerseyNumber = ""
    var sportGender: SportGender = .mens
    var gradYearText = ""
    var highSchool = ""
    var hometown = ""
    var state = ""
    var zipCode = ""
    var hasDateOfBirth = false
    var dateOfBirth = Date(timeIntervalSince1970: 1_136_073_600) // Jan 1, 2006 — starting point before the user picks

    // Physical
    var heightFeetText = ""
    var heightInchesText = ""
    var weightText = ""

    // Academics
    var gpaText = ""
    var satText = ""
    var actText = ""
    var intendedMajor = ""
    var ncaaId = ""

    // Social
    var instagramHandle = ""
    var tiktokHandle = ""

    // Bio
    var bio = ""

    // Contact
    var athleteEmail = ""
    var athletePhone = ""
    var guardianName = ""
    var guardianEmail = ""
    var guardianPhone = ""
    var clubCoachName = ""
    var clubCoachPhone = ""

    // Eligibility & consent
    var consentName = ""
    var consentEmail = ""
    private(set) var consentRecordedAt: String?

    // Publish
    var isPublished = false

    // UI state
    var isLoading = true
    var isSaving = false
    var isUploadingProfilePhoto = false
    var isUploadingGalleryPhoto = false
    var errorMessage: String?
    var infoMessage: String?
    var didSave = false
    var loadFailed = false

    private var currentUserId: String?

    static let galleryLimit = 10
    static let videoLimit = 8
    static let bioLimit = 1000
    static let maxImageSourceBytes = 25 * 1024 * 1024

    var canAddGalleryPhoto: Bool { photos.count < Self.galleryLimit }
    var canAddVideo: Bool { videos.count < Self.videoLimit }

    /// True when the signed-in user has no athlete yet — saving creates one.
    var isCreateMode: Bool { athlete == nil }

    // MARK: - Load

    func load(userId: String) async {
        currentUserId = userId
        if managedAthletes.isEmpty && athlete == nil { isLoading = true }
        errorMessage = nil
        loadFailed = false
        do {
            managedAthletes = try await AthleteService.shared.fetchManagedAthletes(userId: userId)
            let target = managedAthletes.first { $0.id == athlete?.id } ?? managedAthletes.first
            if let target {
                try await loadDetails(for: target)
            } else {
                athlete = nil
                photos = []
                videos = []
                events = []
            }
        } catch {
            errorMessage = error.localizedDescription
            loadFailed = true
        }
        isLoading = false
    }

    func select(athleteId: String) async {
        guard let target = managedAthletes.first(where: { $0.id == athleteId }) else { return }
        errorMessage = nil
        do {
            try await loadDetails(for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDetails(for target: Athlete) async throws {
        athlete = target

        async let photos = AthleteService.shared.fetchPhotos(athleteId: target.id)
        async let videos = AthleteService.shared.fetchVideos(athleteId: target.id)
        async let events = AthleteService.shared.fetchEvents(athleteId: target.id)
        async let contact = AthleteService.shared.fetchContact(athleteId: target.id)

        self.photos = try await photos
        self.videos = try await videos
        self.events = try await events

        populateForm(from: target, contact: try await contact)
    }

    private func populateForm(from athlete: Athlete, contact: AthleteContact?) {
        fullName = athlete.fullName
        position = athlete.position ?? ""
        jerseyNumber = athlete.jerseyNumber ?? ""
        sportGender = SportGender(rawValue: athlete.sportGender ?? "") ?? .mens
        gradYearText = athlete.gradYear.map(String.init) ?? ""
        highSchool = athlete.highSchool ?? ""
        hometown = athlete.hometown ?? ""
        state = athlete.state ?? ""
        zipCode = athlete.zipCode ?? ""
        if let dob = athlete.dateOfBirth?.asDate() {
            hasDateOfBirth = true
            dateOfBirth = dob
        } else {
            hasDateOfBirth = false
        }

        if let inches = athlete.heightInches {
            heightFeetText = String(inches / 12)
            heightInchesText = String(inches % 12)
        } else {
            heightFeetText = ""
            heightInchesText = ""
        }
        weightText = athlete.weightLbs.map(String.init) ?? ""

        gpaText = athlete.gpa.map { String($0) } ?? ""
        satText = athlete.satScore.map(String.init) ?? ""
        actText = athlete.actScore.map(String.init) ?? ""
        intendedMajor = athlete.intendedMajor ?? ""
        ncaaId = athlete.ncaaId ?? ""

        instagramHandle = athlete.instagramHandle ?? ""
        tiktokHandle = athlete.tiktokHandle ?? ""
        bio = athlete.bio ?? ""
        isPublished = athlete.isPublished

        consentName = athlete.guardianConsentName ?? ""
        consentEmail = athlete.guardianConsentEmail ?? ""
        consentRecordedAt = athlete.guardianConsentAt

        athleteEmail = contact?.athleteEmail ?? ""
        athletePhone = contact?.athletePhone ?? ""
        guardianName = contact?.guardianName ?? ""
        guardianEmail = contact?.guardianEmail ?? ""
        guardianPhone = contact?.guardianPhone ?? ""
        clubCoachName = contact?.clubCoachName ?? ""
        clubCoachPhone = contact?.clubCoachPhone ?? ""
    }

    // MARK: - Save

    func save() async {
        errorMessage = nil
        infoMessage = nil

        guard let userId = currentUserId else { return }
        guard let name = trimmedOrNil(fullName) else {
            errorMessage = "Name is required."
            return
        }

        // Non-empty text that fails to parse is an error, not a silent nil —
        // otherwise "18o" in the weight field would wipe the saved value.
        var parseErrors: [String] = []
        let gradYear = parsedInt(gradYearText, label: "Graduation year", errors: &parseErrors)
        let feet = parsedInt(heightFeetText, label: "Height (ft)", errors: &parseErrors)
        let inches = parsedInt(heightInchesText, label: "Height (in)", errors: &parseErrors)
        let heightTotal: Int? = (feet != nil || inches != nil) ? (feet ?? 0) * 12 + (inches ?? 0) : nil
        let weight = parsedInt(weightText, label: "Weight", errors: &parseErrors)
        let gpa = parsedDouble(gpaText, label: "GPA", errors: &parseErrors)
        let sat = parsedInt(satText, label: "SAT", errors: &parseErrors)
        let act = parsedInt(actText, label: "ACT", errors: &parseErrors)

        // Validation ported from the web app's zod schemas
        var errors = parseErrors
        errors += ProfileValidation.validateAthlete(
            fullName: name,
            state: state,
            zipCode: zipCode,
            gradYear: gradYear,
            heightInches: heightTotal,
            weightLbs: weight,
            gpa: gpa,
            satScore: sat,
            actScore: act,
            bio: bio
        )
        errors.append(contentsOf: ProfileValidation.validateContact(
            athleteEmail: athleteEmail,
            athletePhone: athletePhone,
            guardianEmail: guardianEmail,
            guardianPhone: guardianPhone,
            clubCoachPhone: clubCoachPhone
        ))

        // Publishing requires a date of birth (so age rules can't be bypassed
        // by leaving it blank), and minors need guardian consent. The
        // enforce_guardian_consent DB trigger enforces the same rules
        // server-side (supabase/007-launch-hardening.sql).
        let dobString = hasDateOfBirth ? dateOfBirth.asDateOnlyString : nil
        let hasConsentPair = trimmedOrNil(consentName) != nil && trimmedOrNil(consentEmail) != nil
        if isPublished {
            if dobString == nil {
                errors.append("Add a date of birth before publishing — it's required to apply age and consent rules.")
            } else if Compliance.isUnder18(dob: dobString), !hasConsentPair {
                errors.append("A parent or guardian is required to publish a profile for a minor — add their name and email in Eligibility & Consent.")
            }
        }

        guard errors.isEmpty else {
            errorMessage = errors.joined(separator: "\n")
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            // Create the athlete row first when none exists yet
            if athlete == nil {
                athlete = try await AthleteService.shared.createAthlete(userId: userId, fullName: name)
            }
            guard var updated = athlete else { return }

            updated.fullName = name
            updated.position = trimmedOrNil(position)
            updated.jerseyNumber = trimmedOrNil(jerseyNumber)
            updated.sportGender = sportGender.rawValue
            updated.gradYear = gradYear
            updated.highSchool = trimmedOrNil(highSchool)
            updated.hometown = trimmedOrNil(hometown)
            updated.state = trimmedOrNil(state)?.uppercased()
            updated.zipCode = trimmedOrNil(zipCode)
            updated.dateOfBirth = dobString
            updated.heightInches = heightTotal
            updated.weightLbs = weight
            updated.gpa = gpa
            updated.satScore = sat
            updated.actScore = act
            updated.intendedMajor = trimmedOrNil(intendedMajor)
            updated.ncaaId = trimmedOrNil(ncaaId)
            updated.instagramHandle = trimmedOrNil(instagramHandle)
            updated.tiktokHandle = trimmedOrNil(tiktokHandle)
            updated.bio = trimmedOrNil(bio)
            updated.isPublished = isPublished

            // Guardian consent stamping (web parity): set once both fields
            // are present, clear when either is removed
            updated.guardianConsentName = trimmedOrNil(consentName)
            updated.guardianConsentEmail = trimmedOrNil(consentEmail)
            if hasConsentPair {
                if consentRecordedAt == nil {
                    updated.guardianConsentAt = Date.now.toISO8601String()
                }
            } else {
                updated.guardianConsentAt = nil
            }

            // ZIP → coordinates so coach radius search can find the athlete;
            // blank ZIP clears them (web parity)
            if let zip = updated.zipCode {
                if let coordinates = await GeocodingService.geocodeZip(zip) {
                    updated.latitude = coordinates.latitude
                    updated.longitude = coordinates.longitude
                } else {
                    infoMessage = "We couldn't locate that ZIP code — distance search may not find you."
                }
            } else {
                updated.latitude = nil
                updated.longitude = nil
            }

            try await AthleteService.shared.updateAthlete(updated)
            try await AthleteService.shared.saveContact(
                athleteId: updated.id,
                athleteEmail: trimmedOrNil(athleteEmail),
                athletePhone: trimmedOrNil(athletePhone),
                guardianName: trimmedOrNil(guardianName),
                guardianEmail: trimmedOrNil(guardianEmail),
                guardianPhone: trimmedOrNil(guardianPhone),
                clubCoachName: trimmedOrNil(clubCoachName),
                clubCoachPhone: trimmedOrNil(clubCoachPhone)
            )
            athlete = updated
            consentRecordedAt = updated.guardianConsentAt
            if let index = managedAthletes.firstIndex(where: { $0.id == updated.id }) {
                managedAthletes[index] = updated
            } else {
                managedAthletes.append(updated)
            }
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile photo

    func uploadProfilePhoto(imageData: Data) async {
        guard var current = athlete else {
            errorMessage = "Save your profile first, then add a photo."
            return
        }
        guard imageData.count <= Self.maxImageSourceBytes else {
            errorMessage = "That photo is too large (25 MB max)."
            return
        }
        guard let jpegData = processedJPEG(from: imageData, maxDimension: 1200) else {
            errorMessage = "Couldn't read that image. Please try another."
            return
        }

        isUploadingProfilePhoto = true
        defer { isUploadingProfilePhoto = false }

        do {
            let url = try await AthleteService.shared.uploadProfilePhoto(
                data: jpegData,
                userId: current.userId
            )
            current.profilePhotoUrl = url
            try await AthleteService.shared.updateAthlete(current)
            athlete = current
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Gallery

    /// Non-nil while a multi-photo batch is uploading; drives the "Uploading X of Y" label.
    var galleryUploadProgress: (completed: Int, total: Int)?

    func addGalleryPhotos(_ imageDataItems: [Data]) async {
        guard !imageDataItems.isEmpty else { return }
        galleryUploadProgress = (0, imageDataItems.count)
        defer { galleryUploadProgress = nil }

        for (index, data) in imageDataItems.enumerated() {
            await addGalleryPhoto(imageData: data)
            galleryUploadProgress = (index + 1, imageDataItems.count)
        }
    }

    func addGalleryPhoto(imageData: Data) async {
        guard let current = athlete, canAddGalleryPhoto else { return }
        guard imageData.count <= Self.maxImageSourceBytes else {
            errorMessage = "That photo is too large (25 MB max)."
            return
        }
        guard let jpegData = processedJPEG(from: imageData, maxDimension: 1600) else {
            errorMessage = "Couldn't read that image. Please try another."
            return
        }

        isUploadingGalleryPhoto = true
        defer { isUploadingGalleryPhoto = false }

        do {
            let url = try await AthleteService.shared.uploadGalleryPhoto(
                data: jpegData,
                userId: current.userId
            )
            let photo = try await AthleteService.shared.addPhoto(athleteId: current.id, url: url)
            photos.append(photo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCaption(for photo: AthletePhoto, caption: String) async {
        let trimmed = String(caption.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await AthleteService.shared.updatePhotoCaption(
                id: photo.id,
                caption: trimmed.isEmpty ? nil : trimmed
            )
            if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                photos[index].caption = trimmed.isEmpty ? nil : trimmed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePhoto(_ photo: AthletePhoto) async {
        do {
            try await AthleteService.shared.deletePhoto(id: photo.id)
            photos.removeAll { $0.id == photo.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Videos

    /// Error for the Videos section, rendered inline next to the fields —
    /// the shared errorMessage sits at the bottom of a long form where a
    /// rejected URL was effectively invisible.
    var videoError: String?

    /// Returns true on success so the view only clears the input fields
    /// when the video was actually added.
    @discardableResult
    func addVideo(url: String, title: String) async -> Bool {
        videoError = nil
        guard let current = athlete, canAddVideo, let videoUrl = trimmedOrNil(url) else { return false }
        guard let parsed = URL(string: videoUrl), ["http", "https"].contains(parsed.scheme ?? "") else {
            videoError = "Enter a full link starting with https://"
            return false
        }
        do {
            let video = try await AthleteService.shared.addVideo(
                athleteId: current.id,
                url: videoUrl,
                title: trimmedOrNil(title)
            )
            videos.append(video)
            return true
        } catch {
            videoError = error.localizedDescription
            return false
        }
    }

    func deleteVideo(_ video: AthleteVideo) async {
        do {
            try await AthleteService.shared.deleteVideo(id: video.id)
            videos.removeAll { $0.id == video.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Events

    var eventError: String?

    /// Returns true on success so the view only clears its inputs when the
    /// event was actually added.
    @discardableResult
    func addEvent(
        date: Date,
        time: String,
        opponent: String,
        location: String,
        notes: String,
        isMaybe: Bool
    ) async -> Bool {
        eventError = nil
        guard let current = athlete else { return false }
        // A date with no opponent and no location produced a blank,
        // meaningless row on the public profile.
        guard trimmedOrNil(opponent) != nil || trimmedOrNil(location) != nil else {
            eventError = "Add an opponent or a location for this game."
            return false
        }
        do {
            let event = try await AthleteService.shared.addEvent(
                athleteId: current.id,
                eventDate: date.asDateOnlyString,
                eventTime: trimmedOrNil(time),
                opponent: trimmedOrNil(opponent),
                location: trimmedOrNil(location),
                notes: trimmedOrNil(notes),
                isMaybe: isMaybe
            )
            events.append(event)
            events.sort { $0.eventDate < $1.eventDate }
            return true
        } catch {
            eventError = error.localizedDescription
            return false
        }
    }

    func deleteEvent(_ event: AthleteEvent) async {
        do {
            try await AthleteService.shared.deleteEvent(id: event.id)
            events.removeAll { $0.id == event.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parsedInt(_ text: String, label: String, errors: inout [String]) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed) else {
            errors.append("\(label) must be a whole number.")
            return nil
        }
        return value
    }

    private func parsedDouble(_ text: String, label: String, errors: inout [String]) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed) else {
            errors.append("\(label) must be a number.")
            return nil
        }
        return value
    }

    /// Decode, downscale to the longest-edge cap, and re-encode as JPEG 0.85 —
    /// the same pipeline the web app added after Apple's 2.1(a) crash rejection.
    private func processedJPEG(from imageData: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else {
            return image.jpegData(compressionQuality: 0.85)
        }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

extension Date {
    /// Formats as a plain `yyyy-MM-dd` date string for Postgres date columns.
    var asDateOnlyString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Local, matching String.asDate()'s date-only parsing — pickers hand
        // us local-midnight Dates, and formatting those as UTC shifted the
        // stored day (games saved as "today" displayed as yesterday).
        formatter.timeZone = .current
        return formatter.string(from: self)
    }
}
