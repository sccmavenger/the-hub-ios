import SwiftUI
import Supabase

@MainActor
@Observable
final class AuthViewModel {
    var session: Session?
    var currentRoles: [AppRole] = []
    var isLoading = true
    var errorMessage: String?
    /// True when the last role fetch failed — MainTabView shows a retry screen
    /// instead of misrouting the user to the pending-approval dead end.
    var roleLoadFailed = false

    /// The signed-in user's coach application, fetched only when the account
    /// holds no role (that is the only case where it decides routing).
    var coachRequestLoad: CoachRequestLoad = .notLoaded

    var primaryRole: AppRole? {
        if currentRoles.contains(.admin) { return .admin }
        if currentRoles.contains(.coach) { return .coach }
        if currentRoles.contains(.athlete) { return .athlete }
        if currentRoles.contains(.parent) { return .parent }
        return nil
    }

    /// What MainTabView shows. See AccountStateResolver — a role-less account
    /// is a pending coach only if a coach application actually exists.
    var accountRoute: AccountRoute {
        AccountStateResolver.route(
            roles: currentRoles,
            roleLoadFailed: roleLoadFailed,
            coachRequest: coachRequestLoad
        )
    }

    func initialize() async {
        do {
            session = try await supabase.auth.session
            if let userId = session?.user.id.uuidString {
                await loadRoles(userId: userId)
            }
        } catch {
            // No active session — normal on first launch
        }
        isLoading = false

        Task {
            for await (_, newSession) in supabase.auth.authStateChanges {
                self.session = newSession
                if let userId = newSession?.user.id.uuidString {
                    await loadRoles(userId: userId)
                } else {
                    currentRoles = []
                }
            }
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            // Trim: iOS autofill/keyboards commonly append a trailing space,
            // which produced a misleading "Invalid login credentials".
            try await AuthService.shared.signIn(
                email: email.trimmed.lowercased(),
                password: password
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
        } catch {
            // Clear local state regardless — e.g. after account deletion the
            // server-side session is already gone and sign-out throws
        }
        session = nil
        currentRoles = []
        coachRequestLoad = .notLoaded
    }

    /// After an RPC returned the updated application (edit, withdraw), adopt it
    /// without a round trip.
    func applyCoachRequest(_ request: CoachRequest) {
        coachRequestLoad = .loaded(request)
    }

    /// Re-reads the caller's coach application (status screen pull-to-refresh,
    /// "check again" after an admin decision).
    func refreshCoachRequest() async {
        guard let userId = session?.user.id.uuidString
                ?? supabase.auth.currentUser?.id.uuidString else { return }
        await loadCoachRequest(userId: userId)
    }

    func resetPassword(email: String) async -> Bool {
        errorMessage = nil
        do {
            try await AuthService.shared.resetPassword(email: email.trimmed.lowercased())
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Re-fetches roles for the current user — needed right after sign-up,
    /// because role rows are inserted after the session first emits.
    func refreshRoles() async {
        guard let userId = session?.user.id.uuidString
                ?? supabase.auth.currentUser?.id.uuidString else { return }
        await loadRoles(userId: userId)
    }

    private func loadRoles(userId: String) async {
        do {
            let roles = try await AuthService.shared.fetchUserRoles(userId: userId)
            currentRoles = roles.map(\.role)
            roleLoadFailed = false
        } catch {
            // Keep whatever roles we already had — a transient failure on a
            // token refresh must not flip a signed-in user into the
            // no-role/pending state.
            roleLoadFailed = currentRoles.isEmpty
            return
        }
        if currentRoles.isEmpty {
            // Role-less account: a coach applicant, a coach whose membership was
            // suspended, or a misconfigured account. The application decides.
            await loadCoachRequest(userId: userId)
        } else {
            coachRequestLoad = .notLoaded
        }
    }

    private func loadCoachRequest(userId: String) async {
        do {
            let request = try await CoachOnboardingService.shared.fetchMyRequest(userId: userId)
            coachRequestLoad = .loaded(request)
        } catch {
            // Don't downgrade a known state on a transient failure.
            if case .loaded = coachRequestLoad { return }
            coachRequestLoad = .failed
        }
    }
}
