import SwiftUI

/// Review step for a schedule import: the games found in the .ics file, with
/// past games and duplicates pre-deselected. Nothing is written until the
/// user confirms. (TestFlight feedback 2026-09-30.)
struct ICSImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let events: [ICSParser.Event]
    let existing: [AthleteEvent]
    let onImport: ([ICSParser.Event]) async -> (added: Int, skipped: Int)

    @State private var selected: Set<String>
    @State private var isImporting = false
    @State private var result: (added: Int, skipped: Int)?

    init(events: [ICSParser.Event], existing: [AthleteEvent], onImport: @escaping ([ICSParser.Event]) async -> (added: Int, skipped: Int)) {
        self.events = events
        self.existing = existing
        self.onImport = onImport
        let today = Date().asDateOnlyString
        _selected = State(initialValue: Set(events.filter { $0.date >= today && !Self.isDuplicate($0, in: existing) }.map(\.id)))
    }

    private static func isDuplicate(_ event: ICSParser.Event, in existing: [AthleteEvent]) -> Bool {
        let opponent = (event.opponent ?? event.summary).lowercased()
        return existing.contains { $0.eventDate == event.date && ($0.opponent ?? "").lowercased() == opponent }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()
                if let result {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.hubSuccess)
                        Text("Imported \(result.added) game\(result.added == 1 ? "" : "s")")
                            .font(.headline)
                            .foregroundStyle(.white)
                        if result.skipped > 0 {
                            Text("\(result.skipped) skipped as duplicates or blank.")
                                .font(.subheadline)
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                        Button("Done") { dismiss() }
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.hubPrimary)
                            .padding(.top, 8)
                    }
                } else if events.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.hubWarning)
                        Text("No games found")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("The file didn't contain any dated events. Export the schedule again as an .ics calendar file and retry.")
                            .font(.subheadline)
                            .foregroundStyle(Color.hubTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        Section {
                            ForEach(events) { event in
                                let duplicate = Self.isDuplicate(event, in: existing)
                                let past = event.date < Date().asDateOnlyString
                                Button {
                                    if selected.contains(event.id) { selected.remove(event.id) } else { selected.insert(event.id) }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: selected.contains(event.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(event.id) ? Color.hubPrimary : Color.hubTextSecondary)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(event.date.asFormattedDate())
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                                if let time = event.time {
                                                    Text(time).font(.caption).foregroundStyle(Color.hubTextSecondary)
                                                }
                                            }
                                            Text(event.opponent ?? event.summary)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                            if let location = event.location {
                                                Text(location).font(.caption).foregroundStyle(Color.hubTextSecondary).lineLimit(1)
                                            }
                                            if duplicate {
                                                Text("Already on your schedule").font(.caption2).foregroundStyle(Color.hubWarning)
                                            } else if past {
                                                Text("Past game").font(.caption2).foregroundStyle(Color.hubTextSecondary)
                                            }
                                        }
                                    }
                                }
                                .listRowBackground(Color.hubSurface)
                            }
                        } header: {
                            Text("\(events.count) games found · \(selected.count) selected")
                                .foregroundStyle(Color.hubTextSecondary)
                        } footer: {
                            Text("Opponent and location are read from each event's title and location. You can edit or delete games afterwards.")
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Import Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if result == nil, !events.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                isImporting = true
                                let chosen = events.filter { selected.contains($0.id) }
                                result = await onImport(chosen)
                                isImporting = false
                            }
                        } label: {
                            if isImporting {
                                ProgressView().tint(Color.hubPrimary)
                            } else {
                                Text("Import \(selected.count)").bold()
                            }
                        }
                        .disabled(selected.isEmpty || isImporting)
                    }
                }
            }
        }
    }
}
