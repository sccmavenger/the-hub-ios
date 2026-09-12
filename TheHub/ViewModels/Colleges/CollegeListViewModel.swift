import Foundation
import Observation

@MainActor
@Observable
final class CollegeListViewModel {
    private(set) var athleteId: String?
    var interests: [AthleteCollegeInterest] = []
    var isLoading = true
    var errorMessage: String?

    static let collegeLimit = 10

    var canAddCollege: Bool {
        interests.count < Self.collegeLimit
    }

    func load(userId: String) async {
        if athleteId == nil { isLoading = true }
        errorMessage = nil
        do {
            let athlete = try await AthleteService.shared.fetchAthlete(userId: userId)
            athleteId = athlete.id
            interests = try await AthleteService.shared.fetchCollegeInterests(athleteId: athlete.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addCollege(
        name: String,
        division: String?,
        state: String?,
        status: CollegeStatus,
        notes: String?
    ) async {
        guard let athleteId, canAddCollege else { return }
        errorMessage = nil
        do {
            let interest = try await AthleteService.shared.addCollegeInterest(
                athleteId: athleteId,
                collegeName: name,
                division: division,
                state: state,
                status: status.rawValue,
                notes: notes
            )
            interests.append(interest)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCollege(_ interest: AthleteCollegeInterest) async {
        errorMessage = nil
        do {
            try await AthleteService.shared.updateCollegeInterest(interest)
            if let index = interests.firstIndex(where: { $0.id == interest.id }) {
                interests[index] = interest
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCollege(_ interest: AthleteCollegeInterest) async {
        errorMessage = nil
        do {
            try await AthleteService.shared.deleteCollegeInterest(id: interest.id)
            interests.removeAll { $0.id == interest.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
