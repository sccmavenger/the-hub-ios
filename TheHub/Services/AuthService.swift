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

    /// What a College Coach claims at sign-up. Travels as signup metadata;
    /// `handle_new_user` (supabase/014-coach-onboarding.sql) sanitizes it into
    /// a PENDING `coach_requests` row. It grants no role — approval is a
    /// separate, admin-only, server-side step.
    struct CoachApplication {
        var fullName: String
        var title: String
        var institution: String
        var governingBody: GoverningBody
        var division: String?
        var sportGender: SportGender
        var athleticsUrl: String?
        var programUrl: String?
        var phone: String?
        var note: String?

        /// Metadata keys are the trigger's contract; keep them in sync with 014.
        var signupMetadata: [String: AnyJSON] {
            var data: [String: AnyJSON] = [
                "signup_role": .string("coach"),
                "full_name": .string(fullName),
                "coach_title": .string(title),
                "institution": .string(institution),
                "governing_body": .string(governingBody.rawValue),
                "sport_gender": .string(sportGender.rawValue)
            ]
            if let division, !division.isBlank { data["division"] = .string(division) }
            if let athleticsUrl, !athleticsUrl.isBlank { data["athletics_url"] = .string(athleticsUrl) }
            if let programUrl, !programUrl.isBlank { data["program_url"] = .string(programUrl) }
            if let phone, !phone.isBlank { data["phone"] = .string(phone) }
            if let note, !note.isBlank { data["verification_note"] = .string(note) }
            return data
        }
    }

    /// Creates the login account and files the coach application in one
    /// server-side transaction. Returns true when email confirmation is
    /// pending (same posture as athlete/parent sign-up).
    func signUpCoach(email: String, password: String, application: CoachApplication) async throws -> Bool {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: application.signupMetadata,
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
