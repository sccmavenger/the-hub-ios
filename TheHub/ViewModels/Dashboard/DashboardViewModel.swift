import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var managedAthletes: [Athlete] = []
    var selectedAthleteId: String?
    var photos: [AthletePhoto] = []
    var videos: [AthleteVideo] = []
    var events: [AthleteEvent] = []
    var contact: AthleteContact?
    var profileViews = 0
    var coachSaves = 0
    var unreadMessages = 0
    var isLoading = true
    var errorMessage: String?

    private var currentUserId: String?

    var athlete: Athlete? {
        managedAthletes.first { $0.id == selectedAthleteId } ?? managedAthletes.first
    }

    var completenessItems: [ProfileCompleteness.Item] {
        guard let athlete else { return [] }
        return ProfileCompleteness.items(
            athlete: athlete,
            videoCount: videos.count,
            photoCount: photos.count,
            eventCount: events.count,
            hasContact: contact != nil
        )
    }

    var completenessScore: Int {
        ProfileCompleteness.score(items: completenessItems)
    }

    var completenessTone: ProfileCompleteness.Tone {
        ProfileCompleteness.tone(score: completenessScore)
    }

    func load(userId: String) async {
        currentUserId = userId
        if managedAthletes.isEmpty { isLoading = true }
        errorMessage = nil
        do {
            managedAthletes = try await AthleteService.shared.fetchManagedAthletes(userId: userId)
            if selectedAthleteId == nil || !managedAthletes.contains(where: { $0.id == selectedAthleteId }) {
                selectedAthleteId = managedAthletes.first?.id
            }
            if let athlete {
                try await loadDetails(for: athlete, userId: userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func select(athleteId: String) async {
        guard athleteId != selectedAthleteId, let userId = currentUserId else { return }
        selectedAthleteId = athleteId
        guard let athlete else { return }
        errorMessage = nil
        do {
            try await loadDetails(for: athlete, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDetails(for athlete: Athlete, userId: String) async throws {
        async let photos = AthleteService.shared.fetchPhotos(athleteId: athlete.id)
        async let videos = AthleteService.shared.fetchVideos(athleteId: athlete.id)
        async let events = AthleteService.shared.fetchEvents(athleteId: athlete.id)
        async let contact = AthleteService.shared.fetchContact(athleteId: athlete.id)
        async let views = AthleteService.shared.profileViewCount(athleteId: athlete.id)
        // RPC, not a direct count — RLS hides bookmark rows from athletes
        async let saves = AthleteService.shared.fetchBookmarks(athleteId: athlete.id)
        async let unread = AthleteService.shared.unreadMessageCount(
            athleteId: athlete.id,
            currentUserId: userId
        )

        self.photos = try await photos
        self.videos = try await videos
        self.events = try await events
        self.contact = try await contact
        self.profileViews = try await views
        self.coachSaves = try await saves.count
        self.unreadMessages = try await unread
    }
}
