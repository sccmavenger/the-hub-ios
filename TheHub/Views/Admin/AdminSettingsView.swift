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
                    Task { await save(newValue) }
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

    private func save(_ enabled: Bool) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await settings.setCollegeLogosEnabled(enabled)
        } catch {
            errorMessage = "Couldn't update the setting. \(error.localizedDescription)"
            await settings.refresh()
        }
    }
}
