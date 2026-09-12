import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var athlete: Athlete?
    var photos: [AthletePhoto] = []
    var videos: [AthleteVideo] = []
    var events: [AthleteEvent] = []
    var contact: AthleteContact?
    var profileViews90d = 0
    var coachSaves = 0
    var unreadMessages = 0
    var isLoading = true
    var errorMessage: String?

    struct ScoreItem: Identifiable {
        let id: String
        let label: String
        let points: Int
        let isComplete: Bool
    }

    var scoreItems: [ScoreItem] {
        guard let athlete else { return [] }
        return [
            ScoreItem(
                id: "photo", label: "Profile photo", points: 20,
                isComplete: athlete.profilePhotoUrl != nil
            ),
            ScoreItem(
                id: "bio", label: "Bio", points: 15,
                isComplete: !(athlete.bio ?? "").isBlank
            ),
            ScoreItem(
                id: "videos", label: "Highlight video", points: 15,
                isComplete: !videos.isEmpty
            ),
            ScoreItem(
                id: "events", label: "Game schedule", points: 15,
                isComplete: !events.isEmpty
            ),
            ScoreItem(
                id: "gpa", label: "GPA", points: 10,
                isComplete: athlete.gpa != nil
            ),
            ScoreItem(
                id: "size", label: "Height & weight", points: 10,
                isComplete: athlete.heightInches != nil && athlete.weightLbs != nil
            ),
            ScoreItem(
                id: "contact", label: "Contact info", points: 10,
                isComplete: contact != nil
            ),
            ScoreItem(
                id: "gallery", label: "Photo gallery", points: 5,
                isComplete: !photos.isEmpty
            )
        ]
    }

    var completenessScore: Int {
        min(scoreItems.filter(\.isComplete).map(\.points).reduce(0, +), 100)
    }

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
            async let views = AthleteService.shared.profileViewCount(athleteId: athlete.id)
            async let saves = AthleteService.shared.coachSaveCount(athleteId: athlete.id)
            async let unread = AthleteService.shared.unreadMessageCount(
                athleteId: athlete.id,
                currentUserId: userId
            )

            self.photos = try await photos
            self.videos = try await videos
            self.events = try await events
            self.contact = try await contact
            self.profileViews90d = try await views
            self.coachSaves = try await saves
            self.unreadMessages = try await unread
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
