import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ProfileEditViewModel {
    private(set) var athlete: Athlete?
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

    // Publish
    var isPublished = false

    // UI state
    var isLoading = true
    var isSaving = false
    var isUploadingProfilePhoto = false
    var isUploadingGalleryPhoto = false
    var errorMessage: String?
    var didSave = false

    static let galleryLimit = 6

    var canAddGalleryPhoto: Bool {
        photos.count < Self.galleryLimit
    }

    // MARK: - Load

    func load(userId: String) async {
        if athlete == nil { isLoading = true }
        errorMessage = nil
        do {
            let athlete = try await AthleteService.shared.fetchAthlete(userId: userId)
            self.athlete = athlete

            async let photos = AthleteService.shared.fetchPhotos(athleteId: athlete.id)
            async let videos = AthleteService.shared.fetchVideos(athleteId: athlete.id)
            async let events = AthleteService.shared.fetchEvents(athleteId: athlete.id)
            async let contact = AthleteService.shared.fetchContact(athleteId: athlete.id)

            self.photos = try await photos
            self.videos = try await videos
            self.events = try await events

            populateForm(from: athlete, contact: try await contact)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
        guard var updated = athlete else { return }
        errorMessage = nil

        let trimmedName = trimmedOrNil(fullName)
        guard let name = trimmedName else {
            errorMessage = "Name is required."
            return
        }

        isSaving = true
        defer { isSaving = false }

        updated.fullName = name
        updated.position = trimmedOrNil(position)
        updated.jerseyNumber = trimmedOrNil(jerseyNumber)
        updated.sportGender = sportGender.rawValue
        updated.gradYear = Int(gradYearText.trimmingCharacters(in: .whitespaces))
        updated.highSchool = trimmedOrNil(highSchool)
        updated.hometown = trimmedOrNil(hometown)
        updated.state = trimmedOrNil(state)
        updated.zipCode = trimmedOrNil(zipCode)
        updated.dateOfBirth = hasDateOfBirth ? dateOfBirth.asDateOnlyString : nil

        let feet = Int(heightFeetText.trimmingCharacters(in: .whitespaces))
        let inches = Int(heightInchesText.trimmingCharacters(in: .whitespaces))
        if feet != nil || inches != nil {
            updated.heightInches = (feet ?? 0) * 12 + (inches ?? 0)
        } else {
            updated.heightInches = nil
        }
        updated.weightLbs = Int(weightText.trimmingCharacters(in: .whitespaces))

        updated.gpa = Double(gpaText.trimmingCharacters(in: .whitespaces))
        updated.satScore = Int(satText.trimmingCharacters(in: .whitespaces))
        updated.actScore = Int(actText.trimmingCharacters(in: .whitespaces))
        updated.intendedMajor = trimmedOrNil(intendedMajor)
        updated.ncaaId = trimmedOrNil(ncaaId)

        updated.instagramHandle = trimmedOrNil(instagramHandle)
        updated.tiktokHandle = trimmedOrNil(tiktokHandle)
        updated.bio = trimmedOrNil(bio)
        updated.isPublished = isPublished

        do {
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
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile photo

    func uploadProfilePhoto(imageData: Data) async {
        guard var current = athlete else { return }
        guard let jpegData = jpegData(from: imageData) else {
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

    func addGalleryPhoto(imageData: Data) async {
        guard let current = athlete, canAddGalleryPhoto else { return }
        guard let jpegData = jpegData(from: imageData) else {
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
            let photo = try await AthleteService.shared.addPhoto(
                athleteId: current.id,
                url: url
            )
            photos.append(photo)
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

    func addVideo(url: String, title: String) async {
        guard let current = athlete, let videoUrl = trimmedOrNil(url) else { return }
        do {
            let video = try await AthleteService.shared.addVideo(
                athleteId: current.id,
                url: videoUrl,
                title: trimmedOrNil(title)
            )
            videos.append(video)
        } catch {
            errorMessage = error.localizedDescription
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

    func addEvent(
        date: Date,
        time: String,
        opponent: String,
        location: String,
        notes: String,
        isMaybe: Bool
    ) async {
        guard let current = athlete else { return }
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
        } catch {
            errorMessage = error.localizedDescription
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

    private func jpegData(from imageData: Data) -> Data? {
        UIImage(data: imageData)?.jpegData(compressionQuality: 0.85)
    }
}

extension Date {
    /// Formats as a plain `yyyy-MM-dd` date string for Postgres date columns.
    var asDateOnlyString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: self)
    }
}
