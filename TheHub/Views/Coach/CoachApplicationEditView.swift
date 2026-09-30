import SwiftUI

/// Edit / resubmit a coach application. Saves through
/// `update_coach_application`, which re-sanitizes every claim and returns a
/// rejected / needs-info / withdrawn application to `pending`.
struct CoachApplicationEditView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    let request: CoachRequest

    @State private var fullName = ""
    @State private var claims = CoachProgramClaims()
    @State private var isSeeded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if request.status == .needsMoreInformation, let note = request.infoRequestMessage {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("What we need")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(Color.hubTextSecondary)
                            }
                        } icon: {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(Color.hubWarning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.hubWarning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    HubTextField(label: "Full Name", text: $fullName, textContentType: .name, autocapitalization: .words, maxLength: 200)
                    CoachProgramClaimsFields(claims: $claims)

                    if let errorMessage {
                        HubErrorText(message: errorMessage)
                    }

                    HubPrimaryButton(
                        submitLabel,
                        isLoading: isSaving,
                        isDisabled: !claims.isComplete || fullName.isBlank
                    ) {
                        Task { await save() }
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(request.status == .pending ? "Review Application" : "Update Application")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            guard !isSeeded else { return }
            fullName = request.fullName
            claims = CoachProgramClaims(from: request)
            isSeeded = true
        }
    }

    private var submitLabel: String {
        request.status == .pending ? "Save Changes" : "Resubmit Application"
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await CoachOnboardingService.shared.updateApplication(claims, fullName: fullName)
            authViewModel.applyCoachRequest(updated)
            dismiss()
        } catch {
            errorMessage = "Couldn't save your application. \(error.localizedDescription)"
        }
    }
}
