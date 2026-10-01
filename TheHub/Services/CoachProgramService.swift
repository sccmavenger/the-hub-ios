import Foundation
import Observation
import Supabase

/// The verified program a signed-in coach operates under. Read-only on the
/// client: it comes from a `verified` membership joined to an active, verified
/// program — exactly what the rules engine's enforcement path uses (013).
nonisolated struct CoachProgramContext: Codable, Equatable, Identifiable, Sendable {
    let membershipId: String
    let coachUserId: String
    let programId: String
    let institutionName: String
    let governingBody: String
    let division: String?
    let sport: String
    let sportGender: String
    let title: String?
    let membershipRole: String?
    let verifiedAt: String?

    var id: String { membershipId }

    /// "Men's Basketball"
    var programLabel: String {
        let gender = SportGender(rawValue: sportGender)?.displayName
        return [gender, sport.capitalized].compactMap { $0 }.joined(separator: " ")
    }

    /// "NCAA Division I"
    var divisionLabel: String? {
        GoverningBody.divisionLabel(governingBody: governingBody, division: division)
    }

    var roleDisplayName: String? {
        membershipRole.flatMap { CoachMembershipRole(rawValue: $0)?.displayName }
    }

    /// Short chip text for navigation bars: "IronMan · Men's".
    var chipLabel: String {
        let short = institutionName
            .replacingOccurrences(of: "University of ", with: "")
            .replacingOccurrences(of: "University", with: "")
            .trimmingCharacters(in: .whitespaces)
        let gender = SportGender(rawValue: sportGender)?.displayName ?? ""
        return [short.isEmpty ? institutionName : short, gender].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Only a verified membership in an active, verified program counts.
    /// Mirrors sync_coach_role() so the client never shows a program the
    /// server wouldn't honor.
    static func contexts(from memberships: [CoachProgramMembership]) -> [CoachProgramContext] {
        memberships.compactMap { membership in
            guard membership.status == .verified,
                  let program = membership.program,
                  program.active,
                  program.isVerified else { return nil }
            return CoachProgramContext(
                membershipId: membership.id,
                coachUserId: membership.coachUserId,
                programId: program.id,
                institutionName: program.institutionName,
                governingBody: program.governingBody,
                division: program.division,
                sport: program.sport,
                sportGender: program.sportGender,
                title: membership.title,
                membershipRole: membership.membershipRole,
                verifiedAt: membership.verifiedAt
            )
        }
        .sorted { ($0.verifiedAt ?? "") > ($1.verifiedAt ?? "") }
    }

    /// Which program to operate under (spec §5.1, D16): a persisted choice
    /// that is still valid wins; a lone program is implied; several programs
    /// with no valid choice means the coach must pick — never default to the
    /// newest.
    static func resolveSelection(
        persistedProgramId: String?,
        contexts: [CoachProgramContext]
    ) -> CoachProgramContext? {
        if let persistedProgramId,
           let match = contexts.first(where: { $0.programId == persistedProgramId }) {
            return match
        }
        return contexts.count == 1 ? contexts[0] : nil
    }
}

nonisolated enum CoachProgramContextLoad: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded([CoachProgramContext])
    case failed
}

/// Loads the coach's verified program contexts and holds the one they are
/// operating under. Every coach RPC takes that program's id and the server
/// re-validates membership, so this selection is UX state, not authorization.
@MainActor
@Observable
final class CoachProgramService {
    static let shared = CoachProgramService()

    private(set) var load: CoachProgramContextLoad = .notLoaded
    /// The program the coach is working under. Nil while loading, when no
    /// membership is valid, or when several are and none has been chosen.
    private(set) var selectedContext: CoachProgramContext?

    @ObservationIgnored private var userId: String?

    private init() {}

    var contexts: [CoachProgramContext] {
        if case .loaded(let contexts) = load { return contexts }
        return []
    }

    /// Alias kept for Phase 1 call sites.
    var currentContext: CoachProgramContext? { selectedContext }

    /// True when the coach must choose before any program-scoped screen loads.
    var needsProgramChoice: Bool {
        contexts.count > 1 && selectedContext == nil
    }

    var canSwitch: Bool { contexts.count > 1 }

    func refresh(coachUserId: String) async {
        userId = coachUserId
        if case .notLoaded = load { load = .loading }
        do {
            let memberships: [CoachProgramMembership] = try await supabase
                .from("coach_program_memberships")
                .select("*, recruiting_programs(*)")
                .eq("coach_user_id", value: coachUserId)
                .eq("status", value: CoachMembershipStatus.verified.rawValue)
                .execute()
                .value
            let contexts = CoachProgramContext.contexts(from: memberships)
            load = .loaded(contexts)
            selectedContext = CoachProgramContext.resolveSelection(
                persistedProgramId: Self.persistedProgramId(for: coachUserId),
                contexts: contexts
            )
        } catch {
            // Keep a known context on a transient failure.
            if case .loaded = load { return }
            load = .failed
        }
    }

    /// Switches program. Callers re-run their `.task(id: selectedContext?.programId)`.
    func select(_ context: CoachProgramContext) {
        guard contexts.contains(context) else { return }
        selectedContext = context
        if let userId {
            UserDefaults.standard.set(context.programId, forKey: Self.persistenceKey(for: userId))
        }
        MediaService.shared.clear()
    }

    /// Sign-out / account switch.
    func clear() {
        load = .notLoaded
        selectedContext = nil
        userId = nil
    }

    // MARK: - Persistence (per user; routine call, spec §5.1)

    static func persistenceKey(for userId: String) -> String {
        "coach.selectedProgramId.\(userId)"
    }

    private static func persistedProgramId(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: persistenceKey(for: userId))
    }
}
