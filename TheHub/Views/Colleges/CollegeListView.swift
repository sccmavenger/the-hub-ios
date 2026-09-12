import SwiftUI
import Auth

struct CollegeListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = CollegeListViewModel()
    @State private var showingAddSheet = false
    @State private var editingInterest: AthleteCollegeInterest?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.hubGold)
                } else if viewModel.athleteId == nil, let message = viewModel.errorMessage {
                    errorState(message)
                } else if viewModel.interests.isEmpty {
                    emptyState
                } else {
                    collegeList
                }
            }
            .navigationTitle("My Colleges")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Color.hubGold)
                    .disabled(!viewModel.canAddCollege || viewModel.athleteId == nil)
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
        }
        .task { await load() }
    }

    private func load() async {
        guard let userId = authViewModel.session?.user.id.uuidString else { return }
        await viewModel.load(userId: userId)
    }

    private var collegeList: some View {
        List {
            if !viewModel.canAddCollege {
                Text("You've reached the limit of \(CollegeListViewModel.collegeLimit) schools.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(viewModel.interests) { interest in
                Button {
                    editingInterest = interest
                } label: {
                    collegeRow(interest)
                }
                .listRowBackground(Color.hubSurface)
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteCollege(interest) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private func collegeRow(_ interest: AthleteCollegeInterest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(interest.collegeName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(interest.collegeStatus.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.hubGold)
                    .clipShape(Capsule())
            }

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
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 44))
                .foregroundStyle(Color.hubGold)
            Text("No Colleges Yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Add up to \(CollegeListViewModel.collegeLimit) schools you're interested in to track your recruiting journey.")
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Add Your First School") {
                showingAddSheet = true
            }
            .foregroundStyle(Color.hubGold)
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
            .foregroundStyle(Color.hubGold)
        }
    }
}

// MARK: - Add / edit form

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

    private static let divisions = ["D1", "D2", "D3", "NAIA", "JUCO"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HubTextField(label: "College Name", text: $name, autocapitalization: .words)

                        divisionPicker
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
                        .tint(Color.hubGold)
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
                Text("Not set").tag("")
                ForEach(Self.divisions, id: \.self) { division in
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
            .tint(Color.hubGold)
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
