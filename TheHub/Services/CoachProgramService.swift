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
}

nonisolated enum CoachProgramContextLoad: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded([CoachProgramContext])
    case failed
}

/// Loads and exposes the coach's verified program context for Coach Mode,
/// the recruiting rules engine, and the future recruiting board / messaging.
/// Phase 1 uses the most recently verified membership as "current"; the
/// schema supports several (job changes, shared appointments) and a future
/// "Switch Program" can pick among `contexts`.
@MainActor
@Observable
final class CoachProgramService {
    static let shared = CoachProgramService()

    private(set) var load: CoachProgramContextLoad = .notLoaded

    private init() {}

    var contexts: [CoachProgramContext] {
        if case .loaded(let contexts) = load { return contexts }
        return []
    }

    var currentContext: CoachProgramContext? {
        contexts.first
    }

    func refresh(coachUserId: String) async {
        if case .notLoaded = load { load = .loading }
        do {
            let memberships: [CoachProgramMembership] = try await supabase
                .from("coach_program_memberships")
                .select("*, recruiting_programs(*)")
                .eq("coach_user_id", value: coachUserId)
                .eq("status", value: CoachMembershipStatus.verified.rawValue)
                .execute()
                .value
            load = .loaded(CoachProgramContext.contexts(from: memberships))
        } catch {
            // Keep a known context on a transient failure.
            if case .loaded = load { return }
            load = .failed
        }
    }

    /// Sign-out / account switch.
    func clear() {
        load = .notLoaded
    }
}
