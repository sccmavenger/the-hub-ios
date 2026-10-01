import Foundation

/// Discover filters (spec §8.1 / D19). Persisted verbatim as
/// `coach_saved_searches.filters` and encoded 1:1 to the search RPC's
/// parameters by `CoachWorkspaceService`.
nonisolated struct DiscoverFilters: Codable, Equatable, Sendable {
    nonisolated enum PlayingWindow: String, Codable, CaseIterable, Sendable {
        case weekend
        case next7Days = "7d"
        case next30Days = "30d"

        var displayName: String {
            switch self {
            case .weekend: "This weekend"
            case .next7Days: "Next 7 days"
            case .next30Days: "Next 30 days"
            }
        }
    }

    static let radiusOptions = [25, 50, 100, 150, 250]

    var query: String?
    var positions: [String] = []
    var gradYears: [Int] = []
    /// The coach's search center. The ZIP is what they typed; lat/lng come
    /// from GeocodingService and are what the server actually uses.
    var zipCode: String?
    var centerLat: Double?
    var centerLng: Double?
    var radiusMiles: Int?
    var states: [String] = []
    var minHeightInches: Int?
    var minGpa: Double?
    var playingWithin: PlayingWindow?

    init() {}

    enum CodingKeys: String, CodingKey {
        case query, positions
        case gradYears = "grad_years"
        case zipCode = "zip_code"
        case centerLat = "center_lat"
        case centerLng = "center_lng"
        case radiusMiles = "radius_miles"
        case states
        case minHeightInches = "min_height_inches"
        case minGpa = "min_gpa"
        case playingWithin = "playing_within"
    }

    var isEmpty: Bool {
        (query ?? "").isEmpty && positions.isEmpty && gradYears.isEmpty && centerLat == nil
            && states.isEmpty && minHeightInches == nil && minGpa == nil && playingWithin == nil
    }

    var hasRadius: Bool { centerLat != nil && centerLng != nil && radiusMiles != nil }

    /// Number of active filter groups, for a badge on the filter button.
    var activeCount: Int {
        [!(query ?? "").isEmpty, !positions.isEmpty, !gradYears.isEmpty, hasRadius || !states.isEmpty,
         minHeightInches != nil, minGpa != nil, playingWithin != nil].filter { $0 }.count
    }
}

/// A coach's saved Discover filter set. Personal and program-scoped (D27);
/// alerts arrive in 2.1 (D13).
nonisolated struct CoachSavedSearch: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let coachUserId: String
    let programId: String
    var name: String
    var filters: DiscoverFilters
    var alertsEnabled: Bool
    var lastRunAt: String?
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case coachUserId = "coach_user_id"
        case programId = "program_id"
        case name
        case filters
        case alertsEnabled = "alerts_enabled"
        case lastRunAt = "last_run_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
