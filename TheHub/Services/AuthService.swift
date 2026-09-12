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

    func signUpAthlete(email: String, password: String, fullName: String) async throws {
        try await supabase.auth.signUp(email: email, password: password)

        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw AuthError.noUser
        }

        try await supabase
            .from("user_roles")
            .insert(["user_id": userId, "role": "athlete"])
            .execute()

        try await supabase
            .from("athletes")
            .insert([
                "user_id": AnyJSON.string(userId),
                "full_name": .string(fullName),
                "is_published": .bool(false)
            ])
            .execute()
    }

    func signUpParent(email: String, password: String, fullName: String) async throws {
        try await supabase.auth.signUp(email: email, password: password)

        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw AuthError.noUser
        }

        try await supabase
            .from("user_roles")
            .insert(["user_id": userId, "role": "parent"])
            .execute()
    }

    func signUpCoach(
        email: String,
        password: String,
        fullName: String,
        college: String,
        title: String,
        message: String?
    ) async throws {
        try await supabase.auth.signUp(email: email, password: password)

        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw AuthError.noUser
        }

        var request: [String: String] = [
            "user_id": userId,
            "full_name": fullName,
            "email": email,
            "college": college,
            "title": title,
            "status": "pending"
        ]
        if let message { request["message"] = message }

        try await supabase
            .from("coach_requests")
            .insert(request)
            .execute()
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
            "deleteMyAccount",
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
