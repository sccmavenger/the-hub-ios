import SwiftUI

/// Edits a `DiscoverFilters` value (spec §8.2, D19). The ZIP is geocoded here
/// (zippopotam, as the athlete editor does) so the server receives a center
/// point and never an athlete's coordinates in return.
struct DiscoverFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onApply: (DiscoverFilters) -> Void

    @State private var draft: DiscoverFilters
    @State private var locationMode: LocationMode
    @State private var zipText: String
    @State private var statesText: String
    @State private var customPosition = ""
    @State private var isGeocoding = false
    @State private var errorMessage: String?

    private enum LocationMode: String, CaseIterable, Identifiable {
        case anywhere = "Anywhere"
        case radius = "Near a ZIP"
        case states = "States"
        var id: String { rawValue }
    }

    static let positionOptions = ["Guard", "Point Guard", "Shooting Guard", "Wing", "Forward", "Center"]
    static let heightOptions: [Int] = Array(stride(from: 66, through: 86, by: 1))
    static let gpaOptions: [Double] = [2.5, 3.0, 3.25, 3.5, 3.75, 4.0]
    static var gradYearOptions: [Int] {
        let year = Calendar.current.component(.year, from: .now)
        return Array(year...(year + 6))
    }

    init(filters: DiscoverFilters, onApply: @escaping (DiscoverFilters) -> Void) {
        self.onApply = onApply
        _draft = State(initialValue: filters)
        _zipText = State(initialValue: filters.zipCode ?? "")
        _statesText = State(initialValue: filters.states.joined(separator: ", "))
        _locationMode = State(initialValue: filters.hasRadius ? .radius : (filters.states.isEmpty ? .anywhere : .states))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        positionSection
                        classSection
                        locationSection
                        measurablesSection
                        playingSection
                        if let errorMessage {
                            HubErrorText(message: errorMessage)
                        }
                        HubPrimaryButton("Show Athletes", isLoading: isGeocoding) {
                            Task { await apply() }
                        }
                        Button("Clear all filters") {
                            draft = DiscoverFilters()
                            zipText = ""
                            statesText = ""
                            locationMode = .anywhere
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var positionSection: some View {
        filterGroup("Position") {
            FlowLayout(spacing: 8) {
                ForEach(Self.positionOptions, id: \.self) { option in
                    toggleChip(option, isOn: draft.positions.contains(option)) {
                        toggle(&draft.positions, option)
                    }
                }
                ForEach(draft.positions.filter { !Self.positionOptions.contains($0) }, id: \.self) { custom in
                    toggleChip(custom, isOn: true) { toggle(&draft.positions, custom) }
                }
            }
            HStack {
                HubTextField(label: "Other position", text: $customPosition, autocapitalization: .words, maxLength: 30)
                Button("Add") {
                    let value = customPosition.trimmed
                    guard !value.isEmpty else { return }
                    if !draft.positions.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                        draft.positions.append(value)
                    }
                    customPosition = ""
                }
                .font(.subheadline.bold())
                .foregroundStyle(Color.hubPrimary)
                .padding(.top, 22)
            }
        }
    }

    private var classSection: some View {
        filterGroup("Class") {
            FlowLayout(spacing: 8) {
                ForEach(Self.gradYearOptions, id: \.self) { year in
                    toggleChip("'\(String(year).suffix(2))", isOn: draft.gradYears.contains(year)) {
                        toggle(&draft.gradYears, year)
                    }
                }
            }
        }
    }

    private var locationSection: some View {
        filterGroup("Location") {
            Picker("Location", selection: $locationMode) {
                ForEach(LocationMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch locationMode {
            case .anywhere:
                EmptyView()
            case .radius:
                HubTextField(label: "ZIP code", text: $zipText, keyboardType: .numberPad, textContentType: .postalCode, maxLength: 5)
                HubSegmentedField(label: "Within", selection: $draft.radiusMiles, options: DiscoverFilters.radiusOptions) { "\($0) mi" }
                Text("Distances shown are rounded to 5 miles. Athlete locations are never shared.")
                    .font(.caption2)
                    .foregroundStyle(Color.hubTextSecondary)
            case .states:
                HubTextField(label: "States (two-letter codes, comma separated)", text: $statesText, autocapitalization: .characters)
            }
        }
    }

    private var measurablesSection: some View {
        filterGroup("Measurables & academics") {
            HubMenuField(label: "Height at least", selection: $draft.minHeightInches, options: Self.heightOptions, placeholder: "Any") {
                "\($0 / 12)'\($0 % 12)\""
            }
            HubMenuField(label: "GPA at least", selection: $draft.minGpa, options: Self.gpaOptions, placeholder: "Any") {
                $0.formatted(.number.precision(.fractionLength(1...2)))
            }
        }
    }

    private var playingSection: some View {
        filterGroup("Playing soon") {
            HubSegmentedField(label: "Has a game", selection: $draft.playingWithin, options: DiscoverFilters.PlayingWindow.allCases) {
                $0.displayName
            }
            if draft.playingWithin != nil {
                Button("Any time") { draft.playingWithin = nil }
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubPrimary)
            }
        }
    }

    // MARK: - Apply

    private func apply() async {
        errorMessage = nil
        var result = draft
        switch locationMode {
        case .anywhere:
            result.zipCode = nil; result.centerLat = nil; result.centerLng = nil; result.radiusMiles = nil; result.states = []
        case .radius:
            result.states = []
            let zip = zipText.trimmed
            guard zip.count == 5, zip.allSatisfy(\.isNumber) else {
                errorMessage = "Enter a 5-digit ZIP code."
                return
            }
            guard result.radiusMiles != nil else {
                errorMessage = "Choose a distance."
                return
            }
            isGeocoding = true
            let coords = await GeocodingService.geocodeZip(zip)
            isGeocoding = false
            guard let coords else {
                errorMessage = "Couldn't find that ZIP code."
                return
            }
            result.zipCode = zip
            result.centerLat = coords.latitude
            result.centerLng = coords.longitude
        case .states:
            result.zipCode = nil; result.centerLat = nil; result.centerLng = nil; result.radiusMiles = nil
            let codes = statesText
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                .filter { $0.count == 2 }
            guard !codes.isEmpty else {
                errorMessage = "Enter at least one two-letter state code."
                return
            }
            result.states = Array(Set(codes)).sorted()
        }
        onApply(result)
        dismiss()
    }

    // MARK: - Helpers

    private func filterGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func toggleChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(isOn ? .white : Color.hubTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Color.hubPrimary : Color.hubSurfaceElevated)
                .clipShape(Capsule())
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle<T: Equatable>(_ array: inout [T], _ value: T) {
        if let index = array.firstIndex(of: value) {
            array.remove(at: index)
        } else {
            array.append(value)
        }
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
