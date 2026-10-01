import Foundation
import Observation
import Supabase

/// Memo of short-lived signed URLs keyed by storage object path. Pure value so
/// the expiry logic is unit-testable.
nonisolated struct SignedURLCache: Sendable {
    struct Entry: Sendable {
        let url: URL
        let expiresAt: Date
    }

    /// A cached URL is reused only while at least this much life remains, so
    /// an image that starts loading right before expiry still completes.
    let refreshMargin: TimeInterval
    private var entries: [String: Entry] = [:]

    init(refreshMargin: TimeInterval = 5 * 60) {
        self.refreshMargin = refreshMargin
    }

    func url(for path: String, now: Date = .now) -> URL? {
        guard let entry = entries[path],
              entry.expiresAt.timeIntervalSince(now) > refreshMargin else { return nil }
        return entry.url
    }

    mutating func store(_ url: URL, for path: String, expiresAt: Date) {
        entries[path] = Entry(url: url, expiresAt: expiresAt)
    }

    mutating func remove(_ path: String) {
        entries.removeValue(forKey: path)
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    /// Paths that need (re-)signing.
    func stalePaths(in paths: some Sequence<String>, now: Date = .now) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted && url(for: $0, now: now) == nil }
    }
}

/// Protected athlete media (supabase/015-media-paths.sql).
///
/// Rows store the storage object *path*; this service turns paths into
/// 60-minute signed URLs through the Storage API, which enforces the
/// per-photo-row `storage.objects` policies (owner / manager / coach of a
/// published, unblocked athlete). Nothing here decides authorization — an
/// unauthorized path simply fails to sign and the image shows its
/// placeholder. Kingfisher caches images by path (see `HubRemoteImage`), so a
/// fresh signature never refetches bytes already on disk.
@MainActor
@Observable
final class MediaService {
    static let shared = MediaService()

    static let bucket = "athlete-media"
    /// Spec §7: 60 minutes balances the post-block revocation window against
    /// re-signing churn.
    static let expirySeconds = 60 * 60

    @ObservationIgnored private var cache = SignedURLCache()

    private init() {}

    /// Signed URL for one path, or nil when it cannot be signed (not
    /// authorized, missing object, offline).
    func url(for path: String) async -> URL? {
        await urls(for: [path])[path]
    }

    /// Signed URLs for many paths in one Storage call. Missing keys in the
    /// result mean "could not sign"; callers fall back to a placeholder.
    func urls(for paths: [String]) async -> [String: URL] {
        var result: [String: URL] = [:]
        for path in Set(paths) {
            if let cached = cache.url(for: path) { result[path] = cached }
        }
        let stale = cache.stalePaths(in: paths)
        guard !stale.isEmpty else { return result }

        do {
            let signed = try await supabase.storage
                .from(Self.bucket)
                .createSignedURLs(paths: stale, expiresIn: Self.expirySeconds)
            let expiresAt = Date.now.addingTimeInterval(TimeInterval(Self.expirySeconds))
            for item in signed {
                if case .success(let path, let url) = item {
                    cache.store(url, for: path, expiresAt: expiresAt)
                    result[path] = url
                }
            }
        } catch {
            // Storage rejected the batch (e.g. no session). Leave the stale
            // paths unresolved; the UI shows placeholders and retries on the
            // next appearance.
        }
        return result
    }

    /// Forget one path (after replacing a photo) or everything (sign-out,
    /// program switch).
    func invalidate(_ path: String) {
        cache.remove(path)
    }

    func clear() {
        cache.removeAll()
    }
}
