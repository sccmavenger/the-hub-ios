import Foundation

/// Where a signed-in account lands. Resolved from roles *and* coach-application
/// state, so "no role" is never assumed to mean "pending coach" (spec §16).
enum AccountRoute: Equatable {
    /// Roles (and, if needed, the coach application) are still being fetched.
    case loading
    case athlete
    case parent
    /// Approved coach with the `coach` role — Coach Mode.
    case coach
    case admin
    /// Application filed, awaiting admin review.
    case coachPending(CoachRequest)
    /// Admin asked for more information.
    case coachNeedsInformation(CoachRequest)
    case coachRejected(CoachRequest)
    case coachWithdrawn(CoachRequest)
    /// Application was approved but the account no longer holds the coach role:
    /// every verified program membership was suspended/inactivated.
    case coachAccessPaused(CoachRequest)
    /// Roles (or the application) could not be fetched — offer retry.
    case roleLoadError
    /// Signed in, no role, no coach application. A broken account, not a coach.
    case accountConfigurationError
}

/// Load state of the caller's coach application.
enum CoachRequestLoad: Equatable {
    case notLoaded
    case loaded(CoachRequest?)
    case failed
}

enum AccountStateResolver {
    /// Pure function of the fetched state. Role precedence matches the old
    /// `primaryRole` (admin > coach > athlete > parent) so existing accounts
    /// route exactly as before.
    static func route(
        roles: [AppRole],
        roleLoadFailed: Bool,
        coachRequest: CoachRequestLoad
    ) -> AccountRoute {
        if roles.contains(.admin) { return .admin }
        if roles.contains(.coach) { return .coach }
        if roles.contains(.athlete) { return .athlete }
        if roles.contains(.parent) { return .parent }

        // No role. Only now does the coach application matter.
        if roleLoadFailed { return .roleLoadError }

        switch coachRequest {
        case .notLoaded:
            return .loading
        case .failed:
            return .roleLoadError
        case .loaded(nil):
            return .accountConfigurationError
        case .loaded(let request?):
            switch request.status {
            case .pending: return .coachPending(request)
            case .needsMoreInformation: return .coachNeedsInformation(request)
            case .rejected: return .coachRejected(request)
            case .withdrawn: return .coachWithdrawn(request)
            case .approved: return .coachAccessPaused(request)
            }
        }
    }
}
