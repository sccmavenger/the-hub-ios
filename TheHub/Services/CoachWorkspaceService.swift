import Foundation
import Supabase

/// Coach Workspace data layer (spec §15). One method per 016/017 RPC. Every
/// program-scoped call sends `p_program_id`; the server re-checks that the
/// caller holds a verified membership, so a stale or forged id is refused
/// with 'not authorized' and the UI shows the unavailable state.
final class CoachWorkspaceService {
    static let shared = CoachWorkspaceService()

    private init() {}

    // MARK: - Discover

    private struct SearchParams: Encodable {
        let p_program_id: String
        let p_query: String?
        let p_positions: [String]?
        let p_grad_years: [Int]?
        let p_center_lat: Double?
        let p_center_lng: Double?
        let p_radius_miles: Int?
        let p_states: [String]?
        let p_min_height_in: Int?
        let p_min_gpa: Double?
        let p_playing_within: String?
        let p_cursor: AnyJSON?
        let p_limit: Int

        init(programId: String, filters: DiscoverFilters, cursor: AnyJSON?, limit: Int) {
            p_program_id = programId
            p_query = (filters.query ?? "").isBlank ? nil : filters.query?.trimmed
            p_positions = filters.positions.isEmpty ? nil : filters.positions
            p_grad_years = filters.gradYears.isEmpty ? nil : filters.gradYears
            p_center_lat = filters.hasRadius ? filters.centerLat : nil
            p_center_lng = filters.hasRadius ? filters.centerLng : nil
            p_radius_miles = filters.hasRadius ? filters.radiusMiles : nil
            p_states = filters.states.isEmpty ? nil : filters.states
            p_min_height_in = filters.minHeightInches
            p_min_gpa = filters.minGpa
            p_playing_within = filters.playingWithin?.rawValue
            p_cursor = cursor
            p_limit = limit
        }
    }

    /// Server-side search (D12). Pass the previous page's `nextCursor` to continue.
    func search(programId: String, filters: DiscoverFilters, cursor: AnyJSON? = nil, limit: Int = 25) async throws -> AthleteSearchPage {
        try await supabase
            .rpc("search_published_athletes", params: SearchParams(programId: programId, filters: filters, cursor: cursor, limit: limit))
            .execute()
            .value
    }

    private struct DetailParams: Encodable {
        let p_program_id: String
        let p_athlete_id: String
    }

    func detail(programId: String, athleteId: String) async throws -> CoachAthleteDetail {
        try await supabase
            .rpc("coach_athlete_detail", params: DetailParams(p_program_id: programId, p_athlete_id: athleteId))
            .execute()
            .value
    }

    // MARK: - Board mutations (each logs activity server-side)

    private struct SaveParams: Encodable {
        let p_program_id: String
        let p_athlete_id: String
        let p_stage: String
    }

    func saveToBoard(programId: String, athleteId: String, stage: PipelineStage = .watching) async throws -> BoardEntry {
        try await supabase
            .rpc("board_save_athlete", params: SaveParams(p_program_id: programId, p_athlete_id: athleteId, p_stage: stage.rawValue))
            .execute()
            .value
    }

    private struct StageParams: Encodable { let p_entry_id: String; let p_stage: String }
    private struct TagsParams: Encodable { let p_entry_id: String; let p_tags: [String] }
    private struct AssignParams: Encodable { let p_entry_id: String; let p_user_id: String? }
    private struct EntryParams: Encodable { let p_entry_id: String }

    func setStage(entryId: String, stage: PipelineStage) async throws -> BoardEntry {
        try await supabase.rpc("board_set_stage", params: StageParams(p_entry_id: entryId, p_stage: stage.rawValue)).execute().value
    }

    func setTags(entryId: String, tags: [String]) async throws -> BoardEntry {
        try await supabase.rpc("board_set_tags", params: TagsParams(p_entry_id: entryId, p_tags: tags)).execute().value
    }

    /// `userId == nil` unassigns.
    func assign(entryId: String, to userId: String?) async throws -> BoardEntry {
        try await supabase.rpc("board_assign", params: AssignParams(p_entry_id: entryId, p_user_id: userId)).execute().value
    }

    func removeFromBoard(entryId: String) async throws -> BoardEntry {
        try await supabase.rpc("board_remove", params: EntryParams(p_entry_id: entryId)).execute().value
    }

    func restoreToBoard(entryId: String) async throws -> BoardEntry {
        try await supabase.rpc("board_restore", params: EntryParams(p_entry_id: entryId)).execute().value
    }

    // MARK: - Board reads

    private struct BoardListParams: Encodable {
        let p_program_id: String
        let p_stage: String?
        let p_assigned_to: String?
        let p_include_removed: Bool
        let p_cursor: AnyJSON?
        let p_limit: Int
    }

    func boardList(
        programId: String,
        stage: PipelineStage? = nil,
        assignedTo: String? = nil,
        includeRemoved: Bool = false,
        cursor: AnyJSON? = nil,
        limit: Int = 50
    ) async throws -> BoardListPage {
        try await supabase
            .rpc("board_list", params: BoardListParams(
                p_program_id: programId, p_stage: stage?.rawValue, p_assigned_to: assignedTo,
                p_include_removed: includeRemoved, p_cursor: cursor, p_limit: limit))
            .execute()
            .value
    }

    private struct ActivityParams: Encodable {
        let p_program_id: String
        let p_entry_id: String?
        let p_limit: Int
    }

    func boardActivity(programId: String, entryId: String? = nil, limit: Int = 50) async throws -> [BoardActivity] {
        try await supabase
            .rpc("board_activity", params: ActivityParams(p_program_id: programId, p_entry_id: entryId, p_limit: limit))
            .execute()
            .value
    }

    // MARK: - Private notes (owner-only table; RLS enforces)

    func privateNote(athleteId: String) async throws -> CoachPrivateNote? {
        let rows: [CoachPrivateNote] = try await supabase
            .from("coach_private_notes")
            .select()
            .eq("athlete_id", value: athleteId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Empty body deletes the note. Enforces the 2,000-character limit client-side
    /// too; the table check is authoritative.
    func savePrivateNote(coachUserId: String, athleteId: String, body: String) async throws -> CoachPrivateNote? {
        let trimmed = body.trimmed
        if trimmed.isEmpty {
            try await supabase
                .from("coach_private_notes")
                .delete()
                .eq("athlete_id", value: athleteId)
                .execute()
            return nil
        }
        return try await supabase
            .from("coach_private_notes")
            .upsert([
                "coach_user_id": AnyJSON.string(coachUserId),
                "athlete_id": .string(athleteId),
                "body": .string(String(trimmed.prefix(BoardEntry.maxNoteLength)))
            ], onConflict: "coach_user_id,athlete_id")
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Saved searches (personal + program-scoped, D27)

    func savedSearches(programId: String) async throws -> [CoachSavedSearch] {
        try await supabase
            .from("coach_saved_searches")
            .select()
            .eq("program_id", value: programId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createSavedSearch(coachUserId: String, programId: String, name: String, filters: DiscoverFilters) async throws -> CoachSavedSearch {
        try await supabase
            .from("coach_saved_searches")
            .insert([
                "coach_user_id": AnyJSON.string(coachUserId),
                "program_id": .string(programId),
                "name": .string(name.trimmed),
                "filters": try AnyJSON(filters),
                "alerts_enabled": .bool(false)
            ])
            .select()
            .single()
            .execute()
            .value
    }

    func renameSavedSearch(id: String, name: String) async throws {
        try await supabase
            .from("coach_saved_searches")
            .update(["name": AnyJSON.string(name.trimmed)])
            .eq("id", value: id)
            .execute()
    }

    func deleteSavedSearch(id: String) async throws {
        try await supabase
            .from("coach_saved_searches")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// One saved search by id (notification tap). RLS limits this to the
    /// caller's own rows, so a foreign id simply returns nil.
    func savedSearch(id: String) async throws -> CoachSavedSearch? {
        let rows: [CoachSavedSearch] = try await supabase
            .from("coach_saved_searches")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Opt in/out of hourly alerts for new matches (D13). Turning alerts on
    /// seeds a baseline server-side first, so nothing already visible is
    /// replayed as "new".
    func setSavedSearchAlerts(id: String, enabled: Bool) async throws {
        try await supabase
            .from("coach_saved_searches")
            .update(["alerts_enabled": AnyJSON.bool(enabled)])
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Messages (019)

    func inbox(programId: String) async throws -> [CoachInboxThread] {
        try await supabase.rpc("coach_inbox", params: ProgramParams(p_program_id: programId)).execute().value
    }

    private struct SendParams: Encodable {
        let p_program_id: String
        let p_athlete_id: String
        let p_body: String
    }

    /// The only coach send path. A `denied` result means the rules engine
    /// refused the send and recorded the attempt; nothing was delivered.
    func sendMessage(programId: String, athleteId: String, body: String) async throws -> CoachSendResult {
        try await supabase
            .rpc("send_coach_message", params: SendParams(p_program_id: programId, p_athlete_id: athleteId, p_body: body.trimmed))
            .execute()
            .value
    }

    private struct BlockParams: Encodable {
        let p_athlete_id: String
        let p_blocked: Bool
    }

    /// Coaches never receive an athlete's user id; the server resolves it.
    func setAthleteBlocked(athleteId: String, blocked: Bool) async throws {
        try await supabase
            .rpc("coach_block_athlete", params: BlockParams(p_athlete_id: athleteId, p_blocked: blocked))
            .execute()
    }

    // MARK: - Home / Program

    private struct ProgramParams: Encodable { let p_program_id: String }

    func homeSummary(programId: String) async throws -> CoachHomeSummary {
        try await supabase.rpc("coach_home_summary", params: ProgramParams(p_program_id: programId)).execute().value
    }

    func staff(programId: String) async throws -> [ProgramStaffMember] {
        try await supabase.rpc("program_staff", params: ProgramParams(p_program_id: programId)).execute().value
    }
}
