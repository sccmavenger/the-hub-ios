import Foundation
import Supabase

final class AthleteService {
    static let shared = AthleteService()

    private init() {}

    // MARK: - Athlete

    func fetchAthlete(userId: String) async throws -> Athlete {
        try await supabase
            .from("athletes")
            .select()
            .eq("user_id", value: userId)
            .single()
            .execute()
            .value
    }

    /// Athletes the user manages: owned rows plus guardian-linked ones (web parity).
    func fetchManagedAthletes(userId: String) async throws -> [Athlete] {
        let owned: [Athlete] = try await supabase
            .from("athletes")
            .select()
            .eq("user_id", value: userId)
            .order("created_at")
            .execute()
            .value

        let guardianLinks: [AthleteGuardian] = try await supabase
            .from("athlete_guardians")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        let ownedIds = Set(owned.map(\.id))
        let linkedIds = guardianLinks.map(\.athleteId).filter { !ownedIds.contains($0) }
        guard !linkedIds.isEmpty else { return owned }

        let linked: [Athlete] = try await supabase
            .from("athletes")
            .select()
            .in("id", values: linkedIds)
            .execute()
            .value
        return owned + linked
    }

    func createAthlete(userId: String, fullName: String) async throws -> Athlete {
        try await supabase
            .from("athletes")
            .insert([
                "user_id": AnyJSON.string(userId),
                "full_name": .string(fullName),
                "is_published": .bool(false)
            ])
            .select()
            .single()
            .execute()
            .value
    }

    func updateAthlete(_ athlete: Athlete) async throws {
        // Strip server-managed columns so the patch only touches editable fields
        var payload = try AnyJSON(athlete).objectValue ?? [:]
        payload.removeValue(forKey: "id")
        payload.removeValue(forKey: "user_id")
        payload.removeValue(forKey: "created_at")
        payload.removeValue(forKey: "updated_at")

        try await supabase
            .from("athletes")
            .update(payload)
            .eq("id", value: athlete.id)
            .execute()
    }

    // MARK: - NCAA readiness

    func fetchNCAAReadiness(athleteId: String) async throws -> NCAAReadiness? {
        let rows: [NCAAReadiness] = try await supabase
            .from("athlete_ncaa_readiness")
            .select()
            .eq("athlete_id", value: athleteId)
            .execute()
            .value
        return rows.first
    }

    func upsertNCAAReadiness(_ readiness: NCAAReadiness) async throws {
        var payload = try AnyJSON(readiness).objectValue ?? [:]
        payload.removeValue(forKey: "created_at")
        payload.removeValue(forKey: "updated_at")
        // encodeIfPresent drops a cleared GPA — write the null explicitly
        payload["estimated_core_gpa"] = readiness.estimatedCoreGpa.map { AnyJSON.double($0) } ?? .null

        try await supabase
            .from("athlete_ncaa_readiness")
            .upsert(payload, onConflict: "athlete_id")
            .execute()
    }

    // MARK: - Photos

    func fetchPhotos(athleteId: String) async throws -> [AthletePhoto] {
        try await supabase
            .from("athlete_photos")
            .select()
            .eq("athlete_id", value: athleteId)
            .order("created_at")
            .execute()
            .value
    }

    /// Records an uploaded gallery photo by its storage path (supabase/015).
    /// No URL is stored; readers sign the path on demand via MediaService.
    func addPhoto(athleteId: String, storagePath: String, caption: String? = nil) async throws -> AthletePhoto {
        try await supabase
            .from("athlete_photos")
            .insert([
                "athlete_id": AnyJSON.string(athleteId),
                "storage_path": .string(storagePath),
                "caption": caption.map(AnyJSON.string) ?? .null
            ])
            .select()
            .single()
            .execute()
            .value
    }

    func updatePhotoCaption(id: String, caption: String?) async throws {
        try await supabase
            .from("athlete_photos")
            .update(["caption": caption.map(AnyJSON.string) ?? .null])
            .eq("id", value: id)
            .execute()
    }

    func deletePhoto(id: String) async throws {
        try await supabase
            .from("athlete_photos")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Videos

    func fetchVideos(athleteId: String) async throws -> [AthleteVideo] {
        try await supabase
            .from("athlete_videos")
            .select()
            .eq("athlete_id", value: athleteId)
            .order("created_at")
            .execute()
            .value
    }

    func addVideo(athleteId: String, url: String, title: String? = nil) async throws -> AthleteVideo {
        try await supabase
            .from("athlete_videos")
            .insert([
                "athlete_id": AnyJSON.string(athleteId),
                "url": .string(url),
                "title": title.map(AnyJSON.string) ?? .null
            ])
            .select()
            .single()
            .execute()
            .value
    }

    func deleteVideo(id: String) async throws {
        try await supabase
            .from("athlete_videos")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Events

    func fetchEvents(athleteId: String) async throws -> [AthleteEvent] {
        try await supabase
            .from("athlete_events")
            .select()
            .eq("athlete_id", value: athleteId)
            .order("event_date")
            .execute()
            .value
    }

    func addEvent(
        athleteId: String,
        eventDate: String,
        eventTime: String?,
        opponent: String?,
        location: String?,
        notes: String?,
        isMaybe: Bool
    ) async throws -> AthleteEvent {
        try await supabase
            .from("athlete_events")
            .insert([
                "athlete_id": AnyJSON.string(athleteId),
                "event_date": .string(eventDate),
                "event_time": eventTime.map(AnyJSON.string) ?? .null,
                "opponent": opponent.map(AnyJSON.string) ?? .null,
                "location": location.map(AnyJSON.string) ?? .null,
                "notes": notes.map(AnyJSON.string) ?? .null,
                "is_mayb": .bool(isMaybe)
            ])
            .select()
            .single()
            .execute()
            .value
    }

    func deleteEvent(id: String) async throws {
        try await supabase
            .from("athlete_events")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - College interests

    func fetchCollegeInterests(athleteId: String) async throws -> [AthleteCollegeInterest] {
        try await supabase
            .from("athlete_college_interests")
            .select()
            .eq("athlete_id", value: athleteId)
            .order("created_at")
            .execute()
            .value
    }

    func addCollegeInterest(
        athleteId: String,
        collegeName: String,
        division: String?,
        state: String?,
        status: String,
        notes: String?
    ) async throws -> AthleteCollegeInterest {
        try await supabase
            .from("athlete_college_interests")
            .insert([
                "athlete_id": AnyJSON.string(athleteId),
                "college_name": .string(collegeName),
                "division": division.map(AnyJSON.string) ?? .null,
                "state": state.map(AnyJSON.string) ?? .null,
                "status": .string(status),
                "notes": notes.map(AnyJSON.string) ?? .null
            ])
            .select()
            .single()
            .execute()
            .value
    }

    func updateCollegeInterest(_ interest: AthleteCollegeInterest) async throws {
        var payload = try AnyJSON(interest).objectValue ?? [:]
        payload.removeValue(forKey: "id")
        payload.removeValue(forKey: "athlete_id")
        payload.removeValue(forKey: "created_at")
        payload.removeValue(forKey: "updated_at")

        try await supabase
            .from("athlete_college_interests")
            .update(payload)
            .eq("id", value: interest.id)
            .execute()
    }

    func deleteCollegeInterest(id: String) async throws {
        try await supabase
            .from("athlete_college_interests")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Contact

    func fetchContact(athleteId: String) async throws -> AthleteContact? {
        let contacts: [AthleteContact] = try await supabase
            .from("athlete_contacts")
            .select()
            .eq("athlete_id", value: athleteId)
            .limit(1)
            .execute()
            .value
        return contacts.first
    }

    func saveContact(
        athleteId: String,
        athleteEmail: String?,
        athletePhone: String?,
        guardianName: String?,
        guardianEmail: String?,
        guardianPhone: String?,
        clubCoachName: String?,
        clubCoachPhone: String?
    ) async throws {
        let payload: [String: AnyJSON] = [
            "athlete_id": .string(athleteId),
            "athlete_email": athleteEmail.map(AnyJSON.string) ?? .null,
            "athlete_phone": athletePhone.map(AnyJSON.string) ?? .null,
            "guardian_name": guardianName.map(AnyJSON.string) ?? .null,
            "guardian_email": guardianEmail.map(AnyJSON.string) ?? .null,
            "guardian_phone": guardianPhone.map(AnyJSON.string) ?? .null,
            "club_coach_name": clubCoachName.map(AnyJSON.string) ?? .null,
            "club_coach_phone": clubCoachPhone.map(AnyJSON.string) ?? .null
        ]

        try await supabase
            .from("athlete_contacts")
            .upsert(payload, onConflict: "athlete_id")
            .execute()
    }

    // MARK: - Storage

    // Bucket is private. Uploads return the object PATH, which rows store;
    // readers sign it for 60 minutes at read time (MediaService, supabase/015).
    // Long-lived signed URLs are no longer created or stored (TECH-DEBT #6).

    /// Uploads (replacing) the profile photo and returns its storage path.
    func uploadProfilePhoto(data: Data, userId: String) async throws -> String {
        let path = "\(userId)/profile.jpg"
        try await supabase.storage
            .from(MediaService.bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
            )
        MediaService.shared.invalidate(path)   // the bytes changed; drop any cached signature
        return path
    }

    /// Uploads a new gallery photo and returns its storage path.
    func uploadGalleryPhoto(data: Data, userId: String) async throws -> String {
        let path = "\(userId)/gallery/\(UUID().uuidString).jpg"
        try await supabase.storage
            .from(MediaService.bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false)
            )
        return path
    }

    // MARK: - Activity details

    func fetchProfileViews(athleteId: String, limit: Int = 500) async throws -> [AthleteProfileView] {
        try await supabase
            .from("athlete_profile_views")
            .select()
            .eq("athlete_id", value: athleteId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func fetchBookmarks(athleteId: String) async throws -> [BookmarkSummary] {
        try await supabase
            .rpc("bookmarks_for_athlete", params: ["_athlete_id": athleteId])
            .execute()
            .value
    }

    func fetchCoachNames(userIds: [String]) async throws -> [CoachDirectoryEntry] {
        guard !userIds.isEmpty else { return [] }
        return try await supabase
            .rpc("coach_directory_names", params: ["_user_ids": userIds])
            .execute()
            .value
    }

    func fetchMessages(athleteId: String) async throws -> [Message] {
        // Newest 1000, re-sorted oldest-first for display — an unbounded fetch
        // would balloon for heavily recruited athletes.
        let newest: [Message] = try await supabase
            .from("messages")
            .select()
            .eq("athlete_id", value: athleteId)
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
            .value
        return newest.reversed()
    }

    /// Athlete/guardian reply in an existing coach thread. RLS allows this via
    /// can_manage_athlete; the blocked-pair trigger rejects it if either side
    /// has blocked the other.
    /// Inserts a message. The database is the enforcement boundary: blocked
    /// pairs, unpublished athletes, and — for coach senders — the Recruiting
    /// Rules Engine (supabase/013) can all reject the row. A recruiting
    /// rejection surfaces as `RecruitingRulesError.actionProhibited` with the
    /// server's reason; athlete/guardian sends are never subject to it.
    func sendMessage(athleteId: String, coachUserId: String, senderUserId: String, body: String) async throws -> Message {
        do {
            return try await supabase
                .from("messages")
                .insert([
                    "athlete_id": AnyJSON.string(athleteId),
                    "coach_user_id": .string(coachUserId),
                    "sender_user_id": .string(senderUserId),
                    "body": .string(body)
                ])
                .select()
                .single()
                .execute()
                .value
        } catch {
            if let recruiting = RecruitingRulesError.fromServerError(error) {
                throw recruiting
            }
            throw error
        }
    }

    /// Marks all inbound messages in one coach thread as read.
    func markThreadRead(athleteId: String, coachUserId: String, currentUserId: String) async throws {
        try await supabase
            .from("messages")
            .update(["read_at": AnyJSON.string(Date.now.toISO8601String())])
            .eq("athlete_id", value: athleteId)
            .eq("coach_user_id", value: coachUserId)
            .neq("sender_user_id", value: currentUserId)
            .is("read_at", value: nil)
            .execute()
    }

    // MARK: - Activity counts

    /// All-time count, matching the web dashboard tile.
    func profileViewCount(athleteId: String) async throws -> Int {
        let response = try await supabase
            .from("athlete_profile_views")
            .select("*", head: true, count: .exact)
            .eq("athlete_id", value: athleteId)
            .execute()
        return response.count ?? 0
    }

    func coachSaveCount(athleteId: String) async throws -> Int {
        let response = try await supabase
            .from("coach_saved_athletes")
            .select("*", head: true, count: .exact)
            .eq("athlete_id", value: athleteId)
            .execute()
        return response.count ?? 0
    }

    func unreadMessageCount(athleteId: String, currentUserId: String) async throws -> Int {
        let response = try await supabase
            .from("messages")
            .select("*", head: true, count: .exact)
            .eq("athlete_id", value: athleteId)
            .neq("sender_user_id", value: currentUserId)
            .is("read_at", value: nil)
            .execute()
        return response.count ?? 0
    }

    // MARK: - Edge functions

    /// Logs a profile view. The function records it only when the caller may
    /// see the athlete right now (published, not blocked, active coach with a
    /// verified membership in `programId`); refusals are silent 204s.
    func recordProfileView(athleteId: String, programId: String? = nil) async throws {
        var body: [String: String] = ["athleteId": athleteId]
        if let programId { body["programId"] = programId }
        try await supabase.functions.invoke(
            "record-profile-view",
            options: .init(body: body)
        )
    }
}
