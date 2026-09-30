import SwiftUI

/// Approve a coach application by tying it to a *verified* program. The admin
/// either picks an existing program or confirms a new one prefilled from the
/// applicant's claims — editing anything that's wrong — then approves.
/// `approve_coach_request` creates/verifies the program, the membership, the
/// coach role, the request update and the notification in one transaction.
struct CoachApprovalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: CoachRequest
    var onApproved: () async -> Void = {}

    private enum ProgramSource: String, CaseIterable, Identifiable {
        case existing = "Existing program"
        case new = "New program"
        var id: String { rawValue }
    }

    @State private var source: ProgramSource = .existing
    @State private var query = ""
    @State private var results: [RecruitingProgram] = []
    @State private var isSearching = false
    @State private var selectedProgram: RecruitingProgram?

    // New-program draft (prefilled from claims)
    @State private var institution = ""
    @State private var governingBody: GoverningBody? = nil
    @State private var numberedDivision: String? = nil
    @State private var divisionText = ""
    @State private var sportGender: SportGender? = nil
    @State private var athleticsUrl = ""
    @State private var programUrl = ""

    // Membership
    @State private var membershipRole: CoachMembershipRole? = nil
    @State private var verifiedTitle = ""
    @State private var internalNote = ""

    @State private var isSeeded = false
    @State private var isApproving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    claimSummary

                    Picker("Program source", selection: $source) {
                        ForEach(ProgramSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch source {
                    case .existing: existingProgramSection
                    case .new: newProgramSection
                    }

                    membershipSection

                    if let errorMessage {
                        HubErrorText(message: errorMessage)
                    }

                    HubPrimaryButton("Approve & Grant Coach Access", isLoading: isApproving, isDisabled: !canApprove) {
                        Task { await approve() }
                    }
                    Text("Approval is atomic: program verified, membership created, coach role granted, applicant notified.")
                        .font(.caption2)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Approve Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear { seed() }
        .task(id: query) {
            // Debounce typing; the initial query (claimed institution) runs at once.
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    // MARK: - Sections

    private var claimSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Applicant claims")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)
            Text("\(request.fullName) · \(request.title ?? "—")")
                .foregroundStyle(.white)
            Text([request.college, request.programLabel, request.divisionLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var existingProgramSection: some View {
        VStack(spacing: 12) {
            HubTextField(label: "Search programs", text: $query, autocapitalization: .words)

            if isSearching && results.isEmpty {
                ProgressView().tint(Color.hubPrimary)
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Text("No matching program yet.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                    Button("Create it from the claims") {
                        source = .new
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.hubPrimary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(results) { program in
                        Button {
                            selectedProgram = program
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(program.fullLabel)
                                        .foregroundStyle(.white)
                                    HStack(spacing: 6) {
                                        if let division = program.divisionLabel {
                                            Text(division)
                                        }
                                        Text(program.isVerified ? "Verified" : "Unverified — approving verifies it")
                                            .foregroundStyle(program.isVerified ? Color.hubSuccess : Color.hubWarning)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Color.hubTextSecondary)
                                }
                                Spacer()
                                if selectedProgram?.id == program.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.hubPrimary)
                                }
                            }
                            .padding(12)
                        }
                        .background(selectedProgram?.id == program.id ? Color.hubPrimary.opacity(0.12) : Color.hubSurface)
                        if program.id != results.last?.id {
                            Divider().background(Color.hubBorder)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.hubBorder, lineWidth: 1))
            }
        }
    }

    private var newProgramSection: some View {
        VStack(spacing: 16) {
            Text("Confirm each field against the school's official athletics site. Don't approve on the applicant's word alone.")
                .font(.caption)
                .foregroundStyle(Color.hubWarning)
                .frame(maxWidth: .infinity, alignment: .leading)

            HubTextField(label: "Institution", text: $institution, autocapitalization: .words, maxLength: 200)
            HubSegmentedField(label: "Program", selection: $sportGender, options: SportGender.allCases) { $0.displayName }
            HubMenuField(
                label: "Association",
                selection: $governingBody,
                options: GoverningBody.allCases.filter { $0 != .unknown },
                placeholder: "Select…"
            ) { $0.displayName }
            if let governingBody, governingBody.hasNumberedDivisions {
                HubSegmentedField(label: "Division", selection: $numberedDivision, options: GoverningBody.numberedDivisions) {
                    $0.replacingOccurrences(of: "D", with: "Division ")
                }
            } else if let governingBody, governingBody == .other {
                HubTextField(label: "Division / Level (optional)", text: $divisionText, autocapitalization: .words, maxLength: 40)
            }
            HubTextField(label: "Athletics URL (optional)", text: $athleticsUrl, keyboardType: .URL, textContentType: .URL)
            HubTextField(label: "Program URL (optional)", text: $programUrl, keyboardType: .URL, textContentType: .URL)
        }
    }

    private var membershipSection: some View {
        VStack(spacing: 16) {
            Divider().background(Color.hubBorder)
            Text("Membership")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            HubMenuField(
                label: "Role",
                selection: $membershipRole,
                options: CoachMembershipRole.allCases,
                placeholder: "Select…"
            ) { $0.displayName }
            HubTextField(label: "Verified title", text: $verifiedTitle, autocapitalization: .words, maxLength: 120)
            HubMultilineField(label: "Internal note (admins only)", text: $internalNote, placeholder: "e.g. Verified on staff directory 2026-09-30", maxLength: 2000)
        }
    }

    // MARK: - Logic

    private var newProgram: CoachAdminService.NewProgram? {
        guard !institution.isBlank, let governingBody, let sportGender else { return nil }
        let division: String?
        if governingBody.hasNumberedDivisions {
            guard let numberedDivision else { return nil }
            division = numberedDivision
        } else if governingBody == .naia {
            division = nil
        } else {
            division = divisionText.isBlank ? nil : divisionText
        }
        return CoachAdminService.NewProgram(
            institutionName: institution,
            governingBody: governingBody,
            division: division,
            sportGender: sportGender,
            athleticsUrl: CoachProgramClaims.normalizedURL(athleticsUrl),
            programUrl: CoachProgramClaims.normalizedURL(programUrl)
        )
    }

    private var canApprove: Bool {
        switch source {
        case .existing: selectedProgram != nil
        case .new: newProgram != nil
        }
    }

    private func seed() {
        guard !isSeeded else { return }
        isSeeded = true
        query = request.college ?? ""
        institution = request.college ?? ""
        governingBody = GoverningBody(rawValue: request.governingBody ?? "").flatMap { $0 == .unknown ? nil : $0 }
        if governingBody?.hasNumberedDivisions == true {
            numberedDivision = request.division
        } else {
            divisionText = request.division ?? ""
        }
        sportGender = SportGender(rawValue: request.sportGender ?? "")
        athleticsUrl = request.athleticsUrl ?? ""
        programUrl = request.programUrl ?? ""
        verifiedTitle = request.title ?? ""
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await CoachAdminService.shared.searchPrograms(query: query)
            if let selected = selectedProgram, !results.contains(where: { $0.id == selected.id }) {
                selectedProgram = nil
            }
        } catch {
            results = []
        }
    }

    private func approve() async {
        isApproving = true
        errorMessage = nil
        defer { isApproving = false }
        do {
            _ = try await CoachAdminService.shared.approve(
                requestId: request.id,
                existingProgramId: source == .existing ? selectedProgram?.id : nil,
                newProgram: source == .new ? newProgram : nil,
                membershipRole: membershipRole,
                verifiedTitle: verifiedTitle,
                internalNote: internalNote
            )
            await onApproved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
