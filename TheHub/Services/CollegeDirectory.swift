import Foundation
import UIKit

/// National college programs directory — 1,351 NCAA D1/D2/D3, NAIA and NJCAA
/// members, bundled from the web app's colleges-data.ts. Search logic is an
/// exact port of the web's searchColleges (name / common name / acronym / state).
struct College: Decodable, Identifiable, Hashable {
    let name: String
    let state: String
    let division: String
    let common: String?
    let logoId: String?
    let domain: String?

    var id: String { name }
}

final class CollegeDirectory {
    static let shared = CollegeDirectory()

    static let maxCollegeInterests = 10

    private struct Payload: Decodable {
        let colleges: [College]
    }

    private struct IndexEntry {
        let college: College
        let name: String
        let alt: String
        let acronym: String
    }

    private let index: [IndexEntry]

    private init() {
        guard let url = Bundle.main.url(forResource: "Colleges", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            index = []
            return
        }
        index = payload.colleges.map { college in
            IndexEntry(
                college: college,
                name: college.name.lowercased(),
                alt: (college.common ?? "").lowercased(),
                acronym: Self.acronym(college.name)
            )
        }
    }

    /// "Louisiana State University" -> "lsu" (skips filler words).
    private static func acronym(_ name: String) -> String {
        let skip: Set<String> = ["of", "at", "the", "and", "in", "for", "a"]
        let cleaned = String(name.map { char -> Character in
            (char.isLetter || char == " " || char == "-") ? char : " "
        })
        let words = cleaned.split { $0 == " " || $0 == "-" }
        var result = ""
        for word in words {
            let lower = word.lowercased()
            if skip.contains(lower) { continue }
            if let first = lower.first { result.append(first) }
        }
        return result
    }

    func search(_ query: String, division: String? = nil, limit: Int = 12) -> [College] {
        let div = (division?.isEmpty ?? true) || division == "all" ? nil : division
        let pool = index.filter { div == nil || $0.college.division == div }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return pool.prefix(limit).map(\.college) }

        var exact: [College] = []
        var acroExact: [College] = []
        var starts: [College] = []
        var contains: [College] = []

        for entry in pool {
            if entry.alt == q || entry.name == q {
                exact.append(entry.college)
            } else if entry.acronym == q {
                acroExact.append(entry.college)
            } else if entry.name.hasPrefix(q) || entry.alt.hasPrefix(q) || entry.acronym.hasPrefix(q) {
                starts.append(entry.college)
            } else if entry.name.contains(q) || entry.alt.contains(q)
                        || (q.count == 2 && entry.college.state.lowercased() == q) {
                contains.append(entry.college)
            }
            if exact.count + acroExact.count + starts.count + contains.count > limit * 6 { break }
        }
        return Array((exact + acroExact + starts + contains).prefix(limit))
    }

    /// Resolves a stored (free-text) college name to a directory entry.
    ///
    /// College names are stored as text the athlete typed or picked, so they
    /// don't always equal the directory's canonical name — "Louisiana State
    /// University" vs. the directory's "Louisiana State University and
    /// Agricultural and Mechanical College". An exact-only lookup silently
    /// dropped the crest for those.
    ///
    /// Deliberately returns nil rather than guessing when a prefix is
    /// ambiguous ("University of Texas" matches several campuses): showing
    /// the wrong school's logo is worse than showing a monogram.
    func find(named name: String) -> College? {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }

        if let hit = index.first(where: { $0.name == q }) { return hit.college }
        if let hit = index.first(where: { $0.alt == q }) { return hit.college }

        // Stored name is a shortened form of the canonical one.
        let candidates = index.filter { $0.name.hasPrefix(q + " ") }
        if candidates.count == 1 { return candidates[0].college }
        if candidates.count > 1 {
            // Flagship campuses carry the bare acronym as their common name
            // ("LSU"), while satellites qualify it ("LSU Shreveport").
            let queryAcronym = Self.acronym(q)
            let flagships = candidates.filter { $0.alt == queryAcronym }
            if flagships.count == 1 { return flagships[0].college }
        }
        return nil
    }

    /// Logo source chain for college crests, in fallback order.
    ///
    /// Gated behind the admin-controlled `college_logos_enabled` flag
    /// (supabase/008-app-settings.sql). These are third-party trademarks we
    /// hold no license to, so the switch exists to stop serving a school's
    /// mark within minutes of a takedown request instead of waiting on an
    /// App Review cycle. With the flag off — the default, and the state this
    /// app ships in — callers fall back to the letter monogram, which is the
    /// designed empty state.
    @MainActor
    func logoURLs(forCollegeNamed name: String) -> [URL] {
        guard AppSettingsService.shared.collegeLogosEnabled else { return [] }
        guard let college = find(named: name) else { return [] }

        var urls: [URL] = []
        if let id = college.logoId {
            urls.append(URL(string: "https://a.espncdn.com/i/teamlogos/ncaa/500-dark/\(id).png")!)
            urls.append(URL(string: "https://a.espncdn.com/i/teamlogos/ncaa/500/\(id).png")!)
        }
        if let domain = college.domain {
            // School-website favicons (Clearbit's logo API shut down in 2025)
            urls.append(URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128")!)
            urls.append(URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico")!)
        }
        return urls
    }

    /// Loads the best-quality crest for a school, walking the source chain and
    /// rejecting low-resolution images (tiny favicons look pixelated when
    /// stretched). Returns nil when no source passes — callers show initials.
    @MainActor
    final class CrestLoader {
        static let shared = CrestLoader()

        /// Anything below this native pixel size renders visibly pixelated at crest size.
        static let minAcceptablePixels: CGFloat = 64

        private let cache = NSCache<NSString, UIImage>()
        private var known404s: Set<String> = []

        private init() {}

        /// Drops memoized crests and 404 markers — required when the
        /// college-logos flag flips, since both are flag-dependent.
        func clearCache() {
            cache.removeAllObjects()
            known404s.removeAll()
        }

        func crest(forCollegeNamed name: String) async -> UIImage? {
            guard AppSettingsService.shared.collegeLogosEnabled else { return nil }

            let key = name as NSString
            if let cached = cache.object(forKey: key) { return cached }
            if known404s.contains(name) { return nil }

            for url in CollegeDirectory.shared.logoURLs(forCollegeNamed: name) {
                guard let image = await fetch(url) else { continue }
                let nativeMin = min(image.size.width * image.scale, image.size.height * image.scale)
                if nativeMin >= Self.minAcceptablePixels {
                    cache.setObject(image, forKey: key)
                    return image
                }
            }
            known404s.insert(name)
            return nil
        }

        private func fetch(_ url: URL) async -> UIImage? {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count > 200 else { return nil }
            return UIImage(data: data)
        }
    }

    /// Monogram for the crest badge.
    ///
    /// Prefers the school's own web domain, which is the abbreviation the
    /// school chose for itself: ku.edu → "KU", uh.edu → "UH", slu.edu → "SLU",
    /// umkc.edu → "UMKC". Deriving initials from the name instead gets this
    /// wrong in exactly the cases people notice — "University of Kansas" reads
    /// as "UK" (which is Kentucky) when every Kansas fan expects "KU".
    /// Falls back to the search index's acronym, then to leading letters.
    static func crestInitials(_ name: String) -> String {
        if let domain = CollegeDirectory.shared.find(named: name)?.domain,
           let label = domain.split(separator: ".").first {
            let letters = label.filter(\.isLetter).uppercased()
            if (2...4).contains(letters.count) {
                return letters
            }
        }

        let acro = acronym(name).uppercased()
        if (2...4).contains(acro.count) {
            return String(acro.prefix(4))
        }
        // Single-word schools ("Gonzaga") and anything odd fall back to
        // leading letters of the meaningful words.
        let skip: Set<String> = ["university", "college", "of", "the", "at", "and"]
        let words = name
            .split(separator: " ")
            .map(String.init)
            .filter { !skip.contains($0.lowercased()) }
        let source = words.isEmpty ? name.split(separator: " ").map(String.init) : words
        let initials = source.prefix(3).compactMap { $0.first?.uppercased() }.joined()
        return initials.isEmpty ? "•" : initials
    }
}
