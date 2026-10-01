import Foundation
import Observation
import Supabase

/// Short-lived memo of backend decisions. Purely a display optimization:
/// entries expire, are keyed by the exact evaluation inputs, and are never
/// consulted for enforcement (the database is authoritative — spec §25).
struct RecruitingDecisionCache: Sendable {
    struct Key: Hashable, Sendable {
        let athleteId: String
        let action: RecruitingAction
        let governingBody: String?
        let division: String?
    }

    private struct Entry: Sendable {
        let decision: RecruitingDecision
        let fetchedAt: Date
    }

    let lifetime: TimeInterval
    private var entries: [Key: Entry] = [:]

    init(lifetime: TimeInterval = 10 * 60) {
        self.lifetime = lifetime
    }

    /// Returns the cached decision if it is younger than `lifetime`.
    func decision(for key: Key, now: Date = .now) -> RecruitingDecision? {
        guard let entry = entries[key], now.timeIntervalSince(entry.fetchedAt) < lifetime else {
            return nil
        }
        return entry.decision
    }

    mutating func store(_ decision: RecruitingDecision, for key: Key, now: Date = .now) {
        entries[key] = Entry(decision: decision, fetchedAt: now)
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}

/// Client for the backend Recruiting Rules Engine (supabase/010–013).
///
/// Responsibilities: call `evaluate_recruiting_action`, decode the decision,
/// memoize briefly. It contains no rule interpretation — no dates, no
/// divisions, no fallbacks. If the engine flag is off or the call fails, the
/// caller shows "unavailable"; it never invents an allowed/prohibited state.
@MainActor
@Observable
final class RecruitingRulesService {
    static let shared = RecruitingRulesService()

    @ObservationIgnored private var cache = RecruitingDecisionCache()

    private init() {}

    private struct EvaluateParams: Encodable {
        let athleteId: String
        let actionType: String
        let governingBody: String?
        let division: String?

        enum CodingKeys: String, CodingKey {
            case athleteId = "p_athlete_id"
            case actionType = "p_action_type"
            case governingBody = "p_governing_body"
            case division = "p_division"
        }
    }

    /// Evaluates one action for one athlete. `governingBody`/`division` give
    /// the informational context for surfaces with no verified program (NCAA
    /// Journey, Colleges); the server labels such results `client_supplied`
    /// and never hard-blocks on them.
    func evaluate(
        athleteId: String,
        action: RecruitingAction,
        governingBody: String? = nil,
        division: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> RecruitingDecision {
        guard AppSettingsService.shared.recruitingRulesEngineEnabled else {
            throw RecruitingRulesError.engineDisabled
        }

        let key = RecruitingDecisionCache.Key(
            athleteId: athleteId, action: action, governingBody: governingBody, division: division
        )
        if !forceRefresh, let cached = cache.decision(for: key) {
            return cached
        }

        let decision: RecruitingDecision = try await supabase
            .rpc(
                "evaluate_recruiting_action",
                params: EvaluateParams(
                    athleteId: athleteId,
                    actionType: action.rawValue,
                    governingBody: governingBody,
                    division: division
                )
            )
            .execute()
            .value

        cache.store(decision, for: key)
        return decision
    }

    /// View-friendly variant: every failure becomes `.unavailable`.
    func load(
        athleteId: String,
        action: RecruitingAction,
        governingBody: String? = nil,
        division: String? = nil
    ) async -> RecruitingStatusLoad {
        do {
            return .loaded(try await evaluate(
                athleteId: athleteId, action: action, governingBody: governingBody, division: division
            ))
        } catch {
            return .unavailable
        }
    }

    // MARK: - Coach preflight (013/019)

    private struct CoachActionParams: Encodable {
        let p_athlete_id: String
        let p_action_type: String
        let p_program_id: String?
    }

    /// The signed-in coach asks about their own send under the named program.
    /// Same resolver `send_coach_message` and the trigger use, so preflight
    /// and the final check cannot disagree except by the passage of time.
    /// Not memoized: the answer is cheap and must track membership changes.
    func evaluateMyCoachAction(
        athleteId: String,
        action: RecruitingAction = .coachSendRecruitingElectronicCorrespondence,
        programId: String?
    ) async throws -> RecruitingDecision {
        guard AppSettingsService.shared.recruitingRulesEngineEnabled else {
            throw RecruitingRulesError.engineDisabled
        }
        return try await supabase
            .rpc("evaluate_my_coach_action", params: CoachActionParams(
                p_athlete_id: athleteId, p_action_type: action.rawValue, p_program_id: programId))
            .execute()
            .value
    }

    /// View-friendly variant: every failure becomes `.unavailable`.
    func loadMyCoachAction(athleteId: String, programId: String?) async -> RecruitingStatusLoad {
        do {
            return .loaded(try await evaluateMyCoachAction(athleteId: athleteId, programId: programId))
        } catch {
            return .unavailable
        }
    }

    /// Drop memoized decisions (sign-out, profile edits that change grad year
    /// or gender, admin flag changes).
    func clearCache() {
        cache.removeAll()
    }
}
