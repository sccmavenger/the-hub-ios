import Foundation

/// ZIP → coordinates via api.zippopotam.us (free, no API key) — same provider
/// the web app uses so coach radius search sees identical coordinates.
enum GeocodingService {
    struct Coordinates {
        let latitude: Double
        let longitude: Double
    }

    private struct ZippopotamResponse: Decodable {
        struct Place: Decodable {
            let latitude: String
            let longitude: String
        }
        let places: [Place]
    }

    static func geocodeZip(_ zip: String) async -> Coordinates? {
        let trimmed = zip.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 5, trimmed.allSatisfy(\.isNumber),
              let url = URL(string: "https://api.zippopotam.us/us/\(trimmed)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(ZippopotamResponse.self, from: data)
            guard let place = decoded.places.first,
                  let lat = Double(place.latitude),
                  let lon = Double(place.longitude) else { return nil }
            return Coordinates(latitude: lat, longitude: lon)
        } catch {
            return nil
        }
    }
}
