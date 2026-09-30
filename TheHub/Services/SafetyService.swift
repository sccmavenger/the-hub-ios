import Foundation
import Supabase

struct UserBlock: Codable, Identifiable {
    let id: String
    let blockerUserId: String
    let blockedUserId: String
    var reason: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case blockerUserId = "blocker_user_id"
        case blockedUserId = "blocked_user_id"
        case reason
        case createdAt = "created_at"
    }
}

/// Blocking and reporting — Apple guideline 1.2 (user-generated content safety).
final class SafetyService {
    static let shared = SafetyService()

    private init() {}

    /// Report reasons, matching the web app's ReportDialog.
    static let reportReasons = [
        "Harassment or bullying",
        "Inappropriate or sexual content",
        "Spam or scam",
        "Impersonation or fake profile",
        "Violence or threats",
        "Concern about a minor's safety",
        "Something else"
    ]

    // MARK: - Blocks

    func listBlocks(userId: String) async throws -> [UserBlock] {
        try await supabase
            .from("user_blocks")
            .select()
            .eq("blocker_user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func isBlocked(userId: String, blockedUserId: String) async throws -> Bool {
        let blocks: [UserBlock] = try await supabase
            .from("user_blocks")
            .select()
            .eq("blocker_user_id", value: userId)
            .eq("blocked_user_id", value: blockedUserId)
            .limit(1)
            .execute()
            .value
        return !blocks.isEmpty
    }

    func block(userId: String, blockedUserId: String) async throws {
        try await supabase
            .from("user_blocks")
            .upsert(
                ["blocker_user_id": userId, "blocked_user_id": blockedUserId],
                onConflict: "blocker_user_id,blocked_user_id"
            )
            .execute()
    }

    func unblock(userId: String, blockedUserId: String) async throws {
        try await supabase
            .from("user_blocks")
            .delete()
            .eq("blocker_user_id", value: userId)
            .eq("blocked_user_id", value: blockedUserId)
            .execute()
    }

    // MARK: - Reports

    func submitReport(
        reporterUserId: String,
        targetType: String,
        targetId: String,
        athleteId: String?,
        reportedUserId: String?,
        reason: String,
        details: String?
    ) async throws {
        let payload: [String: AnyJSON] = [
            "reporter_user_id": .string(reporterUserId),
            "target_type": .string(targetType),
            "target_id": .string(targetId),
            "athlete_id": athleteId.map(AnyJSON.string) ?? .null,
            "reported_user_id": reportedUserId.map(AnyJSON.string) ?? .null,
            "reason": .string(reason),
            "details": details.map { AnyJSON.string(String($0.prefix(2000))) } ?? .null
        ]
        try await supabase
            .from("content_reports")
            .insert(payload)
            .execute()
    }
}
