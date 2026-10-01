import Foundation
import Testing
@testable import TheHub

/// Client side of the protected-media model (supabase/015). Authorization is
/// tested in SQL (coach-workspace-security.test.sql); these cover the cache
/// that decides when a signed URL is reused vs re-requested, and that rows
/// decode with either a path or a legacy URL.
@Suite("Protected media — client")
struct MediaTests {

    @Test("Cached signed URL is reused while enough life remains, then re-signed")
    func cacheExpiry() throws {
        var cache = SignedURLCache(refreshMargin: 5 * 60)
        let url = try #require(URL(string: "https://example.test/signed?token=abc"))
        let now = Date(timeIntervalSince1970: 1_000_000)
        cache.store(url, for: "uid/profile.jpg", expiresAt: now.addingTimeInterval(60 * 60))

        #expect(cache.url(for: "uid/profile.jpg", now: now) == url)
        #expect(cache.url(for: "uid/profile.jpg", now: now.addingTimeInterval(54 * 60)) == url, "6 min left > 5 min margin")
        #expect(cache.url(for: "uid/profile.jpg", now: now.addingTimeInterval(56 * 60)) == nil, "4 min left: re-sign")
        #expect(cache.url(for: "other.jpg", now: now) == nil)
    }

    @Test("Stale-path selection dedupes and skips fresh entries")
    func stalePaths() throws {
        var cache = SignedURLCache()
        let now = Date.now
        cache.store(try #require(URL(string: "https://x.test/a")), for: "a", expiresAt: now.addingTimeInterval(3600))
        let stale = cache.stalePaths(in: ["a", "b", "b", "c"], now: now)
        #expect(stale == ["b", "c"])
        cache.invalidateForTest("a")
        #expect(cache.stalePaths(in: ["a"], now: now) == ["a"])
    }

    @Test("Photo rows decode with a path only, a legacy URL only, or both")
    func photoDecoding() throws {
        let pathOnly = """
        {"id":"p1","athlete_id":"a1","url":null,"storage_path":"u/gallery/x.jpg","caption":null,"created_at":"2026-10-01T00:00:00+00:00"}
        """
        let legacyOnly = """
        {"id":"p2","athlete_id":"a1","url":"https://legacy.test/sign/x.jpg?token=t","storage_path":null,"caption":"Dunk","created_at":"2026-10-01T00:00:00+00:00"}
        """
        let a = try JSONDecoder().decode(AthletePhoto.self, from: Data(pathOnly.utf8))
        #expect(a.storagePath == "u/gallery/x.jpg" && a.url == nil)
        let b = try JSONDecoder().decode(AthletePhoto.self, from: Data(legacyOnly.utf8))
        #expect(b.storagePath == nil && b.url?.hasPrefix("https://legacy.test") == true)
    }

    @Test("Athlete has a profile photo if either the path or the legacy URL is set")
    func athleteHasProfilePhoto() throws {
        let base = """
        {"id":"a1","user_id":"u1","full_name":"T","is_published":false,"created_at":"2026-10-01T00:00:00+00:00","updated_at":"2026-10-01T00:00:00+00:00"
        """
        let none = try JSONDecoder().decode(Athlete.self, from: Data((base + "}").utf8))
        let path = try JSONDecoder().decode(Athlete.self, from: Data((base + #","profile_photo_path":"u1/profile.jpg"}"#).utf8))
        let legacy = try JSONDecoder().decode(Athlete.self, from: Data((base + #","profile_photo_url":"https://legacy.test/p.jpg"}"#).utf8))
        #expect(!none.hasProfilePhoto)
        #expect(path.hasProfilePhoto && path.profilePhotoPath == "u1/profile.jpg")
        #expect(legacy.hasProfilePhoto)
    }
}

private extension SignedURLCache {
    mutating func invalidateForTest(_ path: String) { remove(path) }
}
