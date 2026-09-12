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

    func addPhoto(athleteId: String, url: String, caption: String? = nil) async throws -> AthletePhoto {
        try await supabase
            .from("athlete_photos")
            .insert([
                "athlete_id": AnyJSON.string(athleteId),
                "url": .string(url),
                "caption": caption.map(AnyJSON.string) ?? .null
            ])
            .select()
            .single()
            .execute()
            .value
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

    func uploadProfilePhoto(data: Data, userId: String) async throws -> String {
        let path = "\(userId)/profile.jpg"
        try await supabase.storage
            .from("athlete-media")
            .upload(
                path,
                data: data,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
            )
        return try publicURL(for: path)
    }

    func uploadGalleryPhoto(data: Data, userId: String) async throws -> String {
        let path = "\(userId)/gallery/\(UUID().uuidString).jpg"
        try await supabase.storage
            .from("athlete-media")
            .upload(
                path,
                data: data,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false)
            )
        return try publicURL(for: path)
    }

    private func publicURL(for path: String) throws -> String {
        try supabase.storage
            .from("athlete-media")
            .getPublicURL(path: path)
            .absoluteString
    }

    // MARK: - Activity counts

    func profileViewCount(athleteId: String, days: Int = 90) async throws -> Int {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let response = try await supabase
            .from("athlete_profile_views")
            .select("*", head: true, count: .exact)
            .eq("athlete_id", value: athleteId)
            .gte("created_at", value: since.toISO8601String())
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

    func recordProfileView(athleteId: String) async throws {
        try await supabase.functions.invoke(
            "recordProfileView",
            options: .init(body: ["athleteId": athleteId])
        )
    }
}
