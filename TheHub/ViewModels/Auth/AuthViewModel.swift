import SwiftUI
import Supabase

@MainActor
@Observable
final class AuthViewModel {
    var session: Session?
    var currentRoles: [AppRole] = []
    var isLoading = true
    var errorMessage: String?

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
            try await AuthService.shared.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
            session = nil
            currentRoles = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetPassword(email: String) async -> Bool {
        errorMessage = nil
        do {
            try await AuthService.shared.resetPassword(email: email)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadRoles(userId: String) async {
        do {
            let roles = try await AuthService.shared.fetchUserRoles(userId: userId)
            currentRoles = roles.map(\.role)
        } catch {
            currentRoles = []
        }
    }
}
