import Foundation
import CoreLocation

// MARK: - Modelle: User / Track-Liste

struct PortalAuthor: Decodable {
    let id: Int
    let displayName: String
    let bio: String?
    let image: String?
}

struct PortalTrackSummary: Identifiable, Decodable {
    let id: Int
    let slug: String
    let title: String?
    let description: String?

    let createdAt: String
    let updatedAt: String

    let isPublic: Bool
    let processingStatus: String

    let recordedAt: String
    let recordedUntil: String

    let duration: Double
    let length: Double

    let numEvents: Int
    let numValid: Int
    let numMeasurements: Int

    let author: PortalAuthor

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case title
        case description
        case createdAt
        case updatedAt
        case processingStatus
        case recordedAt
        case recordedUntil
        case duration
        case length
        case numEvents
        case numValid
        case numMeasurements
        case author
        case isPublic = "public"  // JSON-Feld "public" → Swift-Property "isPublic"
    }
}

struct PortalTrackListResponse: Decodable {
    let trackCount: Int
    let tracks: [PortalTrackSummary]
}

struct PortalTrackDetailResponse: Decodable {
    let track: PortalTrackSummary
}

// MARK: - Modelle: Track-Daten für Karte (/tracks/<slug>/data)

// Events (Überholvorgänge) – GeoJSON FeatureCollection von Points

struct PortalEventProperties: Decodable {
    let distanceOvertaker: Double?
    let distanceStationary: Double?
    let direction: Int?
    let wayId: Int?
    let course: Double?
    let speed: Double?
    let time: String?
    let zone: String?

    enum CodingKeys: String, CodingKey {
        case distanceOvertaker   = "distance_overtaker"
        case distanceStationary  = "distance_stationary"
        case direction
        case wayId               = "way_id"
        case course
        case speed
        case time
        case zone
    }
}

struct PortalEventGeometry: Decodable {
    let type: String?              // "Point"
    let coordinates: [Double]?     // [lon, lat]
}

struct PortalEventFeature: Decodable {
    let type: String?              // "Feature"
    let geometry: PortalEventGeometry?
    let properties: PortalEventProperties?
}

struct PortalEventsFeatureCollection: Decodable {
    let type: String?              // "FeatureCollection"
    let features: [PortalEventFeature]?
}

// Track-Linien: je ein GeoJSON-Feature mit LineString-Geometrie

struct PortalTrackLineGeometry: Decodable {
    let type: String?              // "LineString"
    let coordinates: [[Double]]?   // [[lon, lat], ...]
}

struct PortalTrackFeature: Decodable {
    let type: String?              // "Feature"
    let geometry: PortalTrackLineGeometry?
}

// Top-Level-Objekt von /api/tracks/<slug>/data

struct PortalTrackData: Decodable {
    let events: PortalEventsFeatureCollection?
    let track: PortalTrackFeature?        // gesnappt auf Straße
    let trackRaw: PortalTrackFeature?     // rohe GPS-Route
}

// MARK: - Fehler

enum PortalApiError: Error {
    case invalidBaseUrl
    case invalidURL
    case noHTTPResponse
    case httpError(status: Int, body: String)
}

// MARK: - API-Client

/// API-Client fürs OBS-Portal.
/// - fetchPublicTracks:  GET /api/tracks
/// - fetchMyTracks:      GET /api/tracks/feed
/// - fetchTrackDetail:   GET /api/tracks/<slug>
/// - fetchTrackData:     GET /api/tracks/<slug>/data
final class PortalApiClient {

    private let baseUrl: String

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    // MARK: Öffentliche Tracks

    func fetchPublicTracks(limit: Int = 20, offset: Int = 0) async throws -> PortalTrackListResponse {
        let url = try buildURL(
            path: "/api/tracks",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
        )
        return try await performRequest(url: url, decodeAs: PortalTrackListResponse.self)
    }

    // MARK: Eigene Tracks (Feed)

    /// Eigene Tracks über GET /api/tracks/feed
    /// Wichtig: Parameter `reversed` als String "false", sonst wirft das Backend einen Fehler.
    func fetchMyTracks(limit: Int = 20, offset: Int = 0) async throws -> PortalTrackListResponse {
        let url = try buildURL(
            path: "/api/tracks/feed",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "reversed", value: "false")
            ]
        )
        return try await performRequest(url: url, decodeAs: PortalTrackListResponse.self)
    }

    // MARK: Track-Details

    func fetchTrackDetail(slug: String) async throws -> PortalTrackDetailResponse {
        let url = try buildURL(path: "/api/tracks/\(slug)", queryItems: nil)
        return try await performRequest(url: url, decodeAs: PortalTrackDetailResponse.self)
    }

    // MARK: Track-Daten für Karte

    /// Verarbeitete Track-Daten (Route + Events) aus /api/tracks/<slug>/data
    func fetchTrackData(slug: String) async throws -> PortalTrackData {
        let url = try buildURL(path: "/api/tracks/\(slug)/data", queryItems: nil)
        return try await performRequest(url: url, decodeAs: PortalTrackData.self)
    }

    // MARK: Hilfsfunktionen intern

    private func buildURL(path: String, queryItems: [URLQueryItem]?) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw PortalApiError.invalidBaseUrl
        }

        // WICHTIG:
        // Pfadanteile, die der/die Nutzer:in evtl. eingegeben hat (/api etc.),
        // werden ignoriert. Wir benutzen nur Scheme + Host und hängen
        // dann unseren eigenen Path an.
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PortalApiError.invalidURL
        }
        return url
    }

    private func performRequest<T: Decodable>(url: URL, decodeAs type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw PortalApiError.noHTTPResponse
        }

        // Debug-Logging, damit du siehst, was wirklich zurückkommt
        print("📡 [PortalApiClient] Request:", url.absoluteString)
        print("📡 Status:", http.statusCode)
        print("📡 Body:", String(data: data, encoding: .utf8) ?? "<non-UTF8 / empty>")

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PortalApiError.httpError(status: http.statusCode, body: body)
        }

        // Falls ein Endpunkt wirklich mal einen leeren Body mit 2xx zurückgibt:
        if data.isEmpty {
            if T.self == PortalTrackListResponse.self {
                let empty = PortalTrackListResponse(trackCount: 0, tracks: [])
                return empty as! T
            }
            // Für andere Typen wäre ein leerer Body unerwartet:
            throw PortalApiError.httpError(status: http.statusCode, body: "Leerer Response-Body bei erwarteten Daten.")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys

        return try decoder.decode(T.self, from: data)
    }
}
