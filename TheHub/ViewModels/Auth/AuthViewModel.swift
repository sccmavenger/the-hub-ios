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

    var primaryRole: AppRole? {
        if currentRoles.contains(.admin) { return .admin }
        if currentRoles.contains(.coach) { return .coach }
        if currentRoles.contains(.athlete) { return .athlete }
        if currentRoles.contains(.parent) { return .parent }
        return nil
    }

    var isCoachPendingApproval: Bool {
        session != nil && currentRoles.isEmpty
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
        }
    }
}
