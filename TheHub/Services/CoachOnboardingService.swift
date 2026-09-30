import Foundation
import Supabase

/// The applicant's side of coach verification: read own application, edit /
/// resubmit, withdraw. All writes go through the 014 RPCs — the client never
/// touches `status`, review columns or program linkage directly (RLS and a
/// BEFORE UPDATE guard refuse it anyway).
final class CoachOnboardingService {
    static let shared = CoachOnboardingService()

    private init() {}

    /// The caller's own `coach_requests` row, if any. Nil for accounts that
    /// never applied (an athlete, or a misconfigured account).
    func fetchMyRequest(userId: String) async throws -> CoachRequest? {
        let rows: [CoachRequest] = try await supabase
            .from("coach_requests")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private struct UpdateParams: Encodable {
        let p: [String: AnyJSON]
    }

    /// Saves claim edits. A rejected / needs-info / withdrawn application goes
    /// back to `pending` server-side (resubmission). Returns the updated row.
    func updateApplication(_ claims: CoachProgramClaims, fullName: String?) async throws -> CoachRequest {
        var payload = claims.rpcPayload
        if let fullName, !fullName.isBlank {
            payload["full_name"] = .string(fullName.trimmed)
        }
        return try await supabase
            .rpc("update_coach_application", params: UpdateParams(p: payload))
            .execute()
            .value
    }

    /// Withdraws a pending / needs-info application. Returns the updated row.
    func withdrawApplication() async throws -> CoachRequest {
        try await supabase
            .rpc("withdraw_coach_application")
            .execute()
            .value
    }
}
