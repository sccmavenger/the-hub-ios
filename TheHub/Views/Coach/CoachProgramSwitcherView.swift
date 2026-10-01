import SwiftUI

/// Pick the verified program to operate under (spec §5.3, D16). Presented
/// modally and non-dismissable when a multi-program coach has no valid
/// selection; otherwise reachable from the program chip and the Program tab.
struct CoachProgramSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var programs = CoachProgramService.shared
    var isDismissable = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()
                List {
                    Section {
                        ForEach(programs.contexts) { context in
                            Button {
                                programs.select(context)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(context.institutionName)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text(context.programLabel)
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                        if let division = context.divisionLabel {
                                            Text(division)
                                                .font(.caption)
                                                .foregroundStyle(Color.hubTextSecondary)
                                        }
                                        let role = [context.title, context.roleDisplayName].compactMap { $0 }.joined(separator: " · ")
                                        if !role.isEmpty {
                                            Text(role)
                                                .font(.caption)
                                                .foregroundStyle(Color.hubTextSecondary)
                                        }
                                    }
                                    Spacer()
                                    if programs.selectedContext?.id == context.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.hubPrimary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.hubSurface)
                        }
                    } header: {
                        Text(programs.selectedContext == nil
                             ? "You're verified with more than one program. Choose the one you're recruiting for right now."
                             : "Everything you see in Coach Mode is scoped to this program.")
                            .textCase(nil)
                            .foregroundStyle(Color.hubTextSecondary)
                    } footer: {
                        Text("Changing schools? Contact \(HubSupport.email) and we'll move your verified membership.")
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(programs.selectedContext == nil ? "Choose Your Program" : "Switch Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isDismissable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(!isDismissable)
    }
}

/// Navigation-bar chip naming the selected program; taps open the switcher
/// when the coach holds more than one.
struct CoachProgramChip: View {
    @State private var programs = CoachProgramService.shared
    @State private var showSwitcher = false

    var body: some View {
        if let context = programs.selectedContext {
            Button {
                if programs.canSwitch { showSwitcher = true }
            } label: {
                HStack(spacing: 4) {
                    Text(context.chipLabel)
                        .font(.caption.bold())
                        .lineLimit(1)
                    if programs.canSwitch {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(Color.hubPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.hubPrimary.opacity(0.12))
                .clipShape(Capsule())
            }
            .disabled(!programs.canSwitch)
            .accessibilityLabel("Program: \(context.institutionName) \(context.programLabel)")
            .sheet(isPresented: $showSwitcher) {
                CoachProgramSwitcherView()
            }
        }
    }
}
