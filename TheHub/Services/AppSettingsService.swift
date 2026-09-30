import Foundation
import Observation
import Supabase

/// Remote feature flags read from the `app_settings` table, controlled by
/// admins (see supabase/008-app-settings.sql and 010-recruiting-rules-schema.sql).
///
/// Deliberately FAILS CLOSED: any fetch failure, missing row, or null value
/// leaves flags at their safe defaults.
/// - `collegeLogosEnabled` → false: the risky state is showing third-party
///   trademarks we have no license for, so we show letter monograms instead.
/// - `recruitingRulesEngineEnabled` → false: the app shows "Recruiting status
///   unavailable" rather than any guessed date.
/// - `recruitingRulesEnforcementEnabled` → false: display-only mirror for the
///   admin screen; the database trigger reads the row itself, so this value
///   never gates enforcement on the client.
@MainActor
@Observable
final class AppSettingsService {
    static let shared = AppSettingsService()

    enum Flag: String, CaseIterable {
        case collegeLogos = "college_logos_enabled"
        case recruitingRulesEngine = "recruiting_rules_engine_enabled"
        case recruitingRulesEnforcement = "recruiting_rules_enforcement_enabled"
    }

    /// When true, college crests load official logo artwork; otherwise the
    /// UI shows the school's letter monogram. Admin-controlled kill switch so
    /// a takedown request can be honored in minutes rather than an App Review
    /// cycle.
    private(set) var collegeLogosEnabled = false

    /// When true, Journey/Colleges/Messages ask the backend evaluator for
    /// recruiting status. Rollback path for the Recruiting Rules Engine.
    private(set) var recruitingRulesEngineEnabled = false

    /// Mirrors the server-side hard-block switch (Stage B of the rollout).
    private(set) var recruitingRulesEnforcementEnabled = false

    private var hasLoaded = false

    private init() {}

    private struct SettingRow: Decodable {
        let key: String
        let boolValue: Bool?

        enum CodingKeys: String, CodingKey {
            case key
            case boolValue = "bool_value"
        }
    }

    /// Loads flags once per launch. Safe to call from multiple screens.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        do {
            let rows: [SettingRow] = try await supabase
                .from("app_settings")
                .select("key,bool_value")
                .execute()
                .value

            for flag in Flag.allCases {
                let enabled = rows.first { $0.key == flag.rawValue }?.boolValue ?? false
                apply(flag, enabled: enabled)
            }
            hasLoaded = true
        } catch {
            // Fail closed and allow a later retry.
            for flag in Flag.allCases {
                apply(flag, enabled: false)
            }
        }
    }

    /// Admin-only write. RLS rejects this for everyone else
    /// (supabase/008-app-settings.sql).
    func setFlag(_ flag: Flag, enabled: Bool) async throws {
        try await supabase
            .from("app_settings")
            .update([
                "bool_value": AnyJSON.bool(enabled),
                "updated_by": supabase.auth.currentUser.map { .string($0.id.uuidString) } ?? .null
            ])
            .eq("key", value: flag.rawValue)
            .execute()
        apply(flag, enabled: enabled)
    }

    func setCollegeLogosEnabled(_ enabled: Bool) async throws {
        try await setFlag(.collegeLogos, enabled: enabled)
    }

    /// Resets to safe defaults on sign-out so the next account starts clean.
    func reset() {
        hasLoaded = false
        for flag in Flag.allCases {
            apply(flag, enabled: false)
        }
    }

    private func apply(_ flag: Flag, enabled: Bool) {
        switch flag {
        case .collegeLogos:
            guard enabled != collegeLogosEnabled else { return }
            collegeLogosEnabled = enabled
            // Crest images are memory-cached per school; the cached result is
            // flag-dependent, so it has to go when the flag changes.
            CollegeDirectory.CrestLoader.shared.clearCache()
        case .recruitingRulesEngine:
            guard enabled != recruitingRulesEngineEnabled else { return }
            recruitingRulesEngineEnabled = enabled
            RecruitingRulesService.shared.clearCache()
        case .recruitingRulesEnforcement:
            recruitingRulesEnforcementEnabled = enabled
        }
    }
}
