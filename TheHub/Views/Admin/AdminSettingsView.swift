import SwiftUI

/// Admin-only feature switches. Mirrors the controls in the web admin portal
/// — both write the same `app_settings` rows, so flipping either updates
/// every client on next launch.
struct AdminSettingsView: View {
    @State private var settings = AppSettingsService.shared
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    logoToggleCard
                    recruitingRulesCard
                    if let errorMessage {
                        HubErrorText(message: errorMessage)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Admin Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await settings.refresh() }
    }

    private var logoToggleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("College Crest Logos")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            Toggle(isOn: Binding(
                get: { settings.collegeLogosEnabled },
                set: { newValue in
                    Task { await save(.collegeLogos, newValue) }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show official logos")
                        .foregroundStyle(.white)
                    Text("Off shows each school's letter monogram instead.")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            .tint(Color.hubPrimary)
            .disabled(isSaving)

            Divider().background(Color.hubBorder)

            Label(
                "College logos are third-party trademarks we do not license. Turn this OFF immediately if a school or its licensing agent requests it — the change takes effect for every user without an app update.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(Color.hubWarning)

            if isSaving {
                ProgressView()
                    .tint(Color.hubPrimary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Staged rollout controls for the Recruiting Rules Engine (spec §24):
    /// Stage A = display on / enforcement off; Stage B = both on.
    private var recruitingRulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recruiting Rules Engine")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            Toggle(isOn: Binding(
                get: { settings.recruitingRulesEngineEnabled },
                set: { newValue in
                    Task { await save(.recruitingRulesEngine, newValue) }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show recruiting status")
                        .foregroundStyle(.white)
                    Text("NCAA Journey, Colleges and Messages show rules-based status from the backend. Off shows \"Recruiting status unavailable\".")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            .tint(Color.hubPrimary)
            .disabled(isSaving)

            Toggle(isOn: Binding(
                get: { settings.recruitingRulesEnforcementEnabled },
                set: { newValue in
                    Task { await save(.recruitingRulesEnforcement, newValue) }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enforce coach message rules")
                        .foregroundStyle(.white)
                    Text("The database rejects a verified coach's in-app message when a published rule prohibits it. Off = shadow mode: evaluate and log only.")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            .tint(Color.hubPrimary)
            .disabled(isSaving)

            Divider().background(Color.hubBorder)

            Label(
                "Enforcement only applies to coaches with an admin-verified program. Unverified coaches and unsourced divisions return \"needs review\" and are never blocked.",
                systemImage: "info.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(Color.hubTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func save(_ flag: AppSettingsService.Flag, _ enabled: Bool) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await settings.setFlag(flag, enabled: enabled)
        } catch {
            errorMessage = "Couldn't update the setting. \(error.localizedDescription)"
            await settings.refresh()
        }
    }
}
