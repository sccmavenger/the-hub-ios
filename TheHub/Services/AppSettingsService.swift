import Foundation
import Observation
import Supabase

/// Remote feature flags read from the `app_settings` table, controlled by
/// admins (see supabase/008-app-settings.sql).
///
/// Deliberately FAILS CLOSED: any fetch failure, missing row, or null value
/// leaves flags at their safe defaults. For `collegeLogosEnabled` the safe
/// default is `false`, because the risky state is showing third-party
/// trademarks we have no license for — if we can't confirm the switch is on,
/// we show letter monograms instead.
@MainActor
@Observable
final class AppSettingsService {
    static let shared = AppSettingsService()

    /// When true, college crests load official logo artwork; otherwise the
    /// UI shows the school's letter monogram. Admin-controlled kill switch so
    /// a takedown request can be honored in minutes rather than an App Review
    /// cycle.
    private(set) var collegeLogosEnabled = false

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

            let enabled = rows.first { $0.key == "college_logos_enabled" }?.boolValue ?? false
            apply(collegeLogosEnabled: enabled)
            hasLoaded = true
        } catch {
            // Fail closed and allow a later retry.
            apply(collegeLogosEnabled: false)
        }
    }

    /// Admin-only write. RLS rejects this for everyone else
    /// (supabase/008-app-settings.sql).
    func setCollegeLogosEnabled(_ enabled: Bool) async throws {
        try await supabase
            .from("app_settings")
            .update([
                "bool_value": AnyJSON.bool(enabled),
                "updated_by": supabase.auth.currentUser.map { .string($0.id.uuidString) } ?? .null
            ])
            .eq("key", value: "college_logos_enabled")
            .execute()
        apply(collegeLogosEnabled: enabled)
    }

    /// Resets to safe defaults on sign-out so the next account starts clean.
    func reset() {
        hasLoaded = false
        apply(collegeLogosEnabled: false)
    }

    private func apply(collegeLogosEnabled enabled: Bool) {
        guard enabled != collegeLogosEnabled else { return }
        collegeLogosEnabled = enabled
        // Crest images are memory-cached per school; the cached result is
        // flag-dependent, so it has to go when the flag changes.
        CollegeDirectory.CrestLoader.shared.clearCache()
    }
}
