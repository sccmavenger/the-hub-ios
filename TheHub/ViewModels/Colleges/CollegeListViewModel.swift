import Foundation
import Observation

@MainActor
@Observable
final class CollegeListViewModel {
    var managedAthletes: [Athlete] = []
    var selectedAthleteId: String?
    var interests: [AthleteCollegeInterest] = []
    var isLoading = true
    var errorMessage: String?
    var loadFailed = false

    static let collegeLimit = CollegeDirectory.maxCollegeInterests

    var athlete: Athlete? {
        managedAthletes.first { $0.id == selectedAthleteId } ?? managedAthletes.first
    }

    var canAddCollege: Bool {
        interests.count < Self.collegeLimit
    }

    func load(userId: String) async {
        if managedAthletes.isEmpty { isLoading = true }
        errorMessage = nil
        loadFailed = false
        do {
            managedAthletes = try await AthleteService.shared.fetchManagedAthletes(userId: userId)
            if selectedAthleteId == nil || !managedAthletes.contains(where: { $0.id == selectedAthleteId }) {
                selectedAthleteId = managedAthletes.first?.id
            }
            if let athlete {
                interests = try await AthleteService.shared.fetchCollegeInterests(athleteId: athlete.id)
            } else {
                interests = []
            }
        } catch is CancellationError {
            // A newer refresh superseded this one (e.g. rapid pull-to-refresh) —
            // not an error the user should see.
        } catch {
            errorMessage = error.localizedDescription
            loadFailed = true
        }
        isLoading = false
    }

    func select(athleteId: String) async {
        selectedAthleteId = athleteId
        guard let athlete else { return }
        errorMessage = nil
        do {
            interests = try await AthleteService.shared.fetchCollegeInterests(athleteId: athlete.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addCollege(
        name: String,
        division: String?,
        state: String?,
        status: CollegeStatus,
        notes: String?
    ) async {
        guard let athlete, canAddCollege else { return }
        errorMessage = nil

        // Duplicate check (web parity, case-insensitive)
        let normalized = name.lowercased()
        if interests.contains(where: { $0.collegeName.lowercased() == normalized }) {
            errorMessage = "That school is already on your list."
            return
        }

        do {
            let interest = try await AthleteService.shared.addCollegeInterest(
                athleteId: athlete.id,
                collegeName: String(name.prefix(120)),
                division: division,
                state: state.map { String($0.uppercased().prefix(2)) },
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
