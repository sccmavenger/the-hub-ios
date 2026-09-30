import Foundation
import Supabase

final class AuthService {
    static let shared = AuthService()

    private init() {}

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    // Role, name, and DOB travel as signup metadata; the handle_new_user DB
    // trigger (supabase/007-launch-hardening.sql) creates the user_profiles,
    // user_roles, and athletes rows atomically server-side. With email
    // confirmation enabled there is no session yet, so the client cannot
    // insert rows itself. Returns true when the user must confirm their
    // email before signing in.
    /// Where the confirmation email's link lands after Supabase verifies it.
    /// A universal link: iPhones with the app installed open it directly and
    /// `handleAuthCallback(_:)` exchanges the code for a session (auto
    /// sign-in); any other device gets the site's "Email confirmed" page.
    /// Requires the Associated Domains entitlement (applinks:thehubsh.net),
    /// the AASA file hosted on the site, and membership in the Supabase auth
    /// URI allow list. thehub://auth-callback stays allowed as a fallback.
    static let emailConfirmRedirect = URL(string: "https://thehubsh.net/confirmed")

    func signUpAthlete(email: String, password: String, fullName: String, dateOfBirth: String) async throws -> Bool {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: [
                "signup_role": .string("athlete"),
                "full_name": .string(fullName),
                "date_of_birth": .string(dateOfBirth)
            ],
            redirectTo: Self.emailConfirmRedirect
        )
        return response.session == nil
    }

    func signUpParent(email: String, password: String, fullName: String) async throws -> Bool {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: [
                "signup_role": .string("parent"),
                "full_name": .string(fullName)
            ],
            redirectTo: Self.emailConfirmRedirect
        )
        return response.session == nil
    }

    /// Completes email confirmation when the app is opened via
    /// thehub://auth-callback. Exchanges the auth code in the URL for a
    /// session; AuthViewModel's authStateChanges listener then routes the
    /// signed-in user to their dashboard.
    func handleAuthCallback(_ url: URL) async throws {
        try await supabase.auth.session(from: url)
    }

    func fetchUserRoles(userId: String) async throws -> [UserRole] {
        try await supabase
            .from("user_roles")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    func deleteAccount() async throws {
        try await supabase.functions.invoke(
            "delete-account",
            options: .init(body: ["confirm": "DELETE"])
        )
    }
}

enum AuthError: LocalizedError {
    case noUser
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .noUser: "Could not retrieve user after sign-up. Please try again."
        case .invalidCredentials: "Invalid email or password."
        }
    }
}
