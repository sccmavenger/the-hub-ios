import SwiftUI
import Auth
import Kingfisher

struct CollegeListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = CollegeListViewModel()
    @State private var showingAddSheet = false
    @State private var editingInterest: AthleteCollegeInterest?
    @State private var collegeToDelete: AthleteCollegeInterest?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.hubPrimary)
                } else if viewModel.loadFailed, let message = viewModel.errorMessage {
                    errorState(message)
                } else if viewModel.athlete == nil {
                    noProfileState
                } else {
                    content
                }
            }
            .navigationTitle("My Colleges")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.managedAthletes.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        athleteSwitcher
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Color.hubPrimary)
                    .disabled(!viewModel.canAddCollege || viewModel.athlete == nil)
                    .accessibilityLabel("Add college")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                CollegeFormView(interest: nil) { name, division, state, status, notes in
                    await viewModel.addCollege(
                        name: name,
                        division: division,
                        state: state,
                        status: status,
                        notes: notes
                    )
                }
            }
            .sheet(item: $editingInterest) { interest in
                CollegeFormView(interest: interest) { name, division, state, status, notes in
                    var updated = interest
                    updated.collegeName = name
                    updated.division = division
                    updated.state = state
                    updated.status = status.rawValue
                    updated.notes = notes
                    await viewModel.updateCollege(updated)
                }
            }
            // Deletes are permanent (notes included) — a bare 16pt trash icon
            // was too easy to hit by accident, so confirm first.
            .confirmationDialog(
                "Remove \(collegeToDelete?.collegeName ?? "this school")?",
                isPresented: .init(
                    get: { collegeToDelete != nil },
                    set: { if !$0 { collegeToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let interest = collegeToDelete {
                        Task { await viewModel.deleteCollege(interest) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the school and your notes from your list. This can't be undone.")
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let userId = authViewModel.session?.user.id.uuidString else { return }
        await viewModel.load(userId: userId)
    }

    private var athleteSwitcher: some View {
        Menu {
            ForEach(viewModel.managedAthletes) { athlete in
                Button {
                    Task { await viewModel.select(athleteId: athlete.id) }
                } label: {
                    if athlete.id == viewModel.athlete?.id {
                        Label(athlete.fullName, systemImage: "checkmark")
                    } else {
                        Text(athlete.fullName)
                    }
                }
            }
        } label: {
            Image(systemName: "person.2.circle")
                .foregroundStyle(Color.hubPrimary)
        }
        .accessibilityLabel("Switch athlete")
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                complianceCard

                if let message = viewModel.errorMessage {
                    HubErrorText(message: message)
                }

                if viewModel.interests.isEmpty {
                    emptyListCard
                } else {
                    if !viewModel.canAddCollege {
                        Text("You've reached the limit of \(CollegeListViewModel.collegeLimit) schools.")
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(viewModel.interests) { interest in
                        collegeRow(interest)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    // MARK: - NCAA compliance card (web parity)

    private var complianceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When can coaches contact you?")
                .font(.headline)
                .foregroundStyle(.white)

            Text(Compliance.athleteOutreachNote)
                .font(.subheadline)
                .foregroundStyle(Color.hubPrimary)

            let gender = viewModel.athlete?.sportGender.flatMap(SportGender.init(rawValue:))
            let windows = Compliance.contactWindows(gradYear: viewModel.athlete?.gradYear, gender: gender)

            VStack(spacing: 8) {
                ForEach(windows) { window in
                    HStack(alignment: .top, spacing: 10) {
                        Text(window.division)
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                            .frame(width: 44)
                            .padding(.vertical, 3)
                            .background(window.open ? Color.hubSuccess : Color.hubWarning)
                            .clipShape(Capsule())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.open ? "Contact allowed" : "Not yet")
                                .font(.caption.bold())
                                .foregroundStyle(window.open ? Color.hubSuccess : Color.hubWarning)
                            Text(window.summary)
                                .font(.caption)
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            if let gender {
                let calendar = Compliance.d1Calendar(gender: gender)
                Link(calendar.label, destination: calendar.url)
                    .font(.caption)
                    .foregroundStyle(Color.hubBlue)
            } else {
                Text("Set boys/girls basketball in your profile to see the calendar that applies to you.")
                    .font(.caption)
                    .foregroundStyle(Color.hubWarning)
            }

            Link("NCAA Eligibility Center", destination: Compliance.eligibilityCenterURL)
                .font(.caption)
                .foregroundStyle(Color.hubBlue)

            Text(Compliance.disclaimer(gender: gender))
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)

            // Shown only while crest logos are switched on, since that's the
            // only time third-party marks appear on screen.
            if AppSettingsService.shared.collegeLogosEnabled {
                Text(Compliance.trademarkNotice)
                    .font(.caption2)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        }
        .padding(16)
        .background(Color.hubSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Rows

    private func collegeRow(_ interest: AthleteCollegeInterest) -> some View {
        Button {
            editingInterest = interest
        } label: {
            HStack(spacing: 12) {
                CollegeCrestView(collegeName: interest.collegeName)

                VStack(alignment: .leading, spacing: 4) {
                    Text(interest.collegeName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    let details = [interest.division, interest.state].compactMap(\.self).joined(separator: " · ")
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(Color.hubTextSecondary)
                    }

                    if let notes = interest.notes, !notes.isBlank {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(interest.collegeStatus.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.hubPrimary)
                        .clipShape(Capsule())

                    Button {
                        collegeToDelete = interest
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(Color.hubError)
                    }
                    .accessibilityLabel("Remove \(interest.collegeName)")
                }
            }
            .padding(14)
            .background(Color.hubSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var emptyListCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.system(size: 36))
                .foregroundStyle(Color.hubPrimary)
            Text("No Colleges Yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Add up to \(CollegeListViewModel.collegeLimit) schools you're interested in. Coaches from a listed program get notified when your profile is published.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
            Button("Add Your First School") {
                showingAddSheet = true
            }
            .foregroundStyle(Color.hubPrimary)
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.hubSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var noProfileState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubPrimary)
            Text("Create a Profile First")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Your college list is tied to an athlete profile. Create one from the Profile tab.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubWarning)
            Text("Couldn't load your colleges")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await load() }
            }
            .foregroundStyle(Color.hubPrimary)
        }
    }
}

// MARK: - College crest (ESPN/Clearbit with initials fallback)

struct CollegeCrestView: View {
    let collegeName: String
    var size: CGFloat = 44

    @State private var crest: UIImage?

    var body: some View {
        Group {
            if let crest {
                Image(uiImage: crest)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                initialsBadge
            }
        }
        .task(id: collegeName) {
            crest = await CollegeDirectory.CrestLoader.shared.crest(forCollegeNamed: collegeName)
        }
    }

    private var initialsBadge: some View {
        Text(CollegeDirectory.crestInitials(collegeName))
            // Scales with the badge; 4-letter monograms (UMKC) must shrink to
            // fit the small 28pt search badge rather than truncate to "U…".
            .font(.system(size: size * 0.30, weight: .bold))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .foregroundStyle(Color.hubPrimary)
            .frame(width: size, height: size)
            // Tinted fill + border so the tile reads on both the card
            // (hubSurface) and the suggestion list (hubSurfaceElevated) —
            // a neutral fill was invisible against one or the other.
            .background(Color.hubPrimary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.hubPrimary.opacity(0.35), lineWidth: 1)
            )
    }
}

// MARK: - Add / edit form with national-directory typeahead

private struct CollegeFormView: View {
    let interest: AthleteCollegeInterest?
    let onSave: (String, String?, String?, CollegeStatus, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var division = ""
    @State private var state = ""
    @State private var status: CollegeStatus = .interested
    @State private var notes = ""
    @State private var isSaving = false
    @State private var suggestionsDismissed = false

    private var suggestions: [College] {
        guard interest == nil, !suggestionsDismissed,
              name.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        return CollegeDirectory.shared.search(name, division: division.isEmpty ? nil : division)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        divisionPicker

                        VStack(alignment: .leading, spacing: 6) {
                            HubTextField(label: "College Name", text: $name, autocapitalization: .words)
                                .onChange(of: name) { suggestionsDismissed = false }

                            if !suggestions.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(suggestions) { college in
                                        Button {
                                            name = college.name
                                            state = college.state
                                            division = college.division
                                            suggestionsDismissed = true
                                        } label: {
                                            HStack(spacing: 10) {
                                                CollegeCrestView(collegeName: college.name, size: 28)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(college.name)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.white)
                                                        .multilineTextAlignment(.leading)
                                                    Text("\(college.division) · \(college.state)")
                                                        .font(.caption)
                                                        .foregroundStyle(Color.hubTextSecondary)
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                        }
                                        Divider().background(Color.hubBorder)
                                    }
                                }
                                .background(Color.hubSurfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Text("Search 1,300+ NCAA, NAIA and JUCO programs — or type any school that isn't listed.")
                                .font(.caption2)
                                .foregroundStyle(Color.hubTextSecondary)
                        }

                        statusPicker

                        HubTextField(label: "State", text: $state, autocapitalization: .characters)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.hubTextSecondary)

                            TextEditor(text: $notes)
                                .frame(minHeight: 100)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(Color.hubSurface)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.hubBorder, lineWidth: 1)
                                )
                                .onChange(of: notes) {
                                    notes = String(notes.prefix(1000))
                                }
                        }

                        HubPrimaryButton(
                            interest == nil ? "Add College" : "Save Changes",
                            isLoading: isSaving,
                            isDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty
                        ) {
                            save()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(interest == nil ? "Add College" : "Edit College")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.hubPrimary)
                }
            }
        }
        .onAppear {
            guard let interest else { return }
            name = interest.collegeName
            division = interest.division ?? ""
            state = interest.state ?? ""
            status = interest.collegeStatus
            notes = interest.notes ?? ""
        }
    }

    private var divisionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Division")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            Picker("Division", selection: $division) {
                Text("All").tag("")
                ForEach(Compliance.divisions, id: \.self) { division in
                    Text(division).tag(division)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var statusPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            Picker("Status", selection: $status) {
                ForEach(CollegeStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.hubPrimary)
        }
    }

    private func save() {
        isSaving = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedState = state.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await onSave(
                trimmedName,
                division.isEmpty ? nil : division,
                trimmedState.isEmpty ? nil : trimmedState,
                status,
                trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            dismiss()
        }
    }
}
