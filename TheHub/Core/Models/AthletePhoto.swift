import Foundation

nonisolated struct AthletePhoto: Codable, Identifiable, Sendable {
    let id: String
    let athleteId: String
    /// Legacy 1-year signed URL (rows written before supabase/015). Nil for new rows.
    var url: String?
    /// Storage object path in the private `athlete-media` bucket; resolved to a
    /// short-lived signed URL at read time (see MediaService). Nil only for
    /// legacy rows whose object could not be verified during backfill.
    var storagePath: String?
    var caption: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case url
        case storagePath = "storage_path"
        case caption
        case createdAt = "created_at"
    }
}
