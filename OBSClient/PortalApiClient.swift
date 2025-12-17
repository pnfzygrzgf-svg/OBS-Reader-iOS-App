import Foundation
import CoreLocation

// =====================================================
// MARK: - Modelle: User / Track-Liste
// =====================================================

/// Autor-Infos, die in Track-Responses eingebettet sind.
struct PortalAuthor: Decodable {
    /// Numerische ID im Portal
    let id: Int

    /// Anzeigename (Profilname)
    let displayName: String

    /// Optionaler Profiltext
    let bio: String?

    /// Optionaler Pfad/URL zu einem Bild
    let image: String?
}

/// Kurzinfos zu einem Track (kommt in Listen-Endpoints zurück).
/// `Identifiable` erleichtert die Verwendung in SwiftUI Listen.
struct PortalTrackSummary: Identifiable, Decodable {
    let id: Int
    let slug: String
    let title: String?
    let description: String?

    /// Zeitfelder kommen als String (z.B. ISO 8601) – kann später auf `Date` umgestellt werden.
    let createdAt: String
    let updatedAt: String

    /// JSON-Key heißt "public" → in Swift mappen wir auf isPublic
    let isPublic: Bool

    /// Status z.B. "done", "processing", ...
    let processingStatus: String

    /// Aufnahmezeitraum
    let recordedAt: String
    let recordedUntil: String

    /// Dauer/Länge (Einheiten portalabhängig; oft Sekunden/Meter)
    let duration: Double
    let length: Double

    /// Zähler/Statistiken aus dem Backend
    let numEvents: Int
    let numValid: Int
    let numMeasurements: Int

    /// Eingebetteter Autor
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

/// Response-Wrapper für Track-Listen (Feed)
struct PortalTrackListResponse: Decodable {
    let trackCount: Int
    let tracks: [PortalTrackSummary]
}

/// Detail-Endpoint liefert oft { track: { ... } }
struct PortalTrackDetailResponse: Decodable {
    let track: PortalTrackSummary
}

// =====================================================
// MARK: - Modelle: Track-Daten für Karte (/api/tracks/<slug>/data)
// =====================================================

// -----------------------------------------------------
// MARK: Events (Überholvorgänge) – GeoJSON FeatureCollection von Points
// -----------------------------------------------------

/// Properties eines Event-Punktes (GeoJSON Feature properties).
/// Viele Felder optional, weil nicht jedes Event alles enthält.
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

/// GeoJSON Geometry für Event-Punkte.
/// coordinates typischerweise [lon, lat]
struct PortalEventGeometry: Decodable {
    let type: String?              // "Point"
    let coordinates: [Double]?     // [lon, lat]
}

/// GeoJSON Feature für ein Event.
struct PortalEventFeature: Decodable {
    let type: String?              // "Feature"
    let geometry: PortalEventGeometry?
    let properties: PortalEventProperties?
}

/// FeatureCollection: enthält mehrere Event-Features.
struct PortalEventsFeatureCollection: Decodable {
    let type: String?              // "FeatureCollection"
    let features: [PortalEventFeature]?
}

// -----------------------------------------------------
// MARK: Track-Linien: GeoJSON LineString
// -----------------------------------------------------

/// Geometry für Track-Linie.
/// coordinates: Array von [lon, lat] Punkten
struct PortalTrackLineGeometry: Decodable {
    let type: String?              // "LineString"
    let coordinates: [[Double]]?   // [[lon, lat], ...]
}

/// Feature, das eine Track-Linie enthält.
struct PortalTrackFeature: Decodable {
    let type: String?              // "Feature"
    let geometry: PortalTrackLineGeometry?
}

/// Top-Level-Objekt von /api/tracks/<slug>/data
/// - events: Event-Punkte
/// - track: gesnappt (map-matching) auf Straße
/// - trackRaw: rohe GPS Route
struct PortalTrackData: Decodable {
    let events: PortalEventsFeatureCollection?
    let track: PortalTrackFeature?        // gesnappt auf Straße
    let trackRaw: PortalTrackFeature?     // rohe GPS-Route
}

// =====================================================
// MARK: - Fehler
// =====================================================

/// Fehler, die beim Aufbau der URL oder bei HTTP-Responses auftreten können.
enum PortalApiError: Error {
    case invalidBaseUrl
    case invalidURL
    case noHTTPResponse
    case httpError(status: Int, body: String)
}

// =====================================================
// MARK: - API-Client (nur “My Tracks”)
// =====================================================

/// API-Client fürs OBS-Portal – fokussiert auf **eigene Tracks**.
///
/// Unterstützte Endpunkte:
/// - fetchMyTracks:      GET /api/tracks/feed
/// - fetchTrackDetail:   GET /api/tracks/<slug>
/// - fetchTrackData:     GET /api/tracks/<slug>/data
///
/// Nicht enthalten:
/// - Öffentliche Tracks (GET /api/tracks), da du diese nicht benötigst.
final class PortalApiClient {

    /// Basis-URL des Portals, z.B. "https://portal.openbikesensor.org"
    /// Erwartung: Scheme + Host (+ optional Port). Pfad wird in buildURL überschrieben.
    private let baseUrl: String

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    // -------------------------------------------------
    // MARK: Eigene Tracks (Feed)
    // -------------------------------------------------

    /// Lädt nur die Tracks des eingeloggten Users aus GET /api/tracks/feed.
    ///
    /// - Parameters:
    ///   - limit:  Anzahl Einträge pro “Seite”
    ///   - offset: Startindex für Pagination (0, 20, 40, ...)
    ///
    /// Wichtig:
    /// - Parameter `reversed` muss als String "false" gesendet werden,
    ///   sonst wirft das Backend (laut Erfahrung) einen Fehler.
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

    // -------------------------------------------------
    // MARK: Track-Details
    // -------------------------------------------------

    /// Lädt Detailinfos zu einem Track aus GET /api/tracks/<slug>
    func fetchTrackDetail(slug: String) async throws -> PortalTrackDetailResponse {
        let url = try buildURL(path: "/api/tracks/\(slug)", queryItems: nil)
        return try await performRequest(url: url, decodeAs: PortalTrackDetailResponse.self)
    }

    // -------------------------------------------------
    // MARK: Track-Daten für Karte
    // -------------------------------------------------

    /// Lädt verarbeitete Track-Daten (Route + Events) aus GET /api/tracks/<slug>/data
    func fetchTrackData(slug: String) async throws -> PortalTrackData {
        let url = try buildURL(path: "/api/tracks/\(slug)/data", queryItems: nil)
        return try await performRequest(url: url, decodeAs: PortalTrackData.self)
    }

    // =====================================================
    // MARK: - Hilfsfunktionen intern
    // =====================================================

    /// Baut eine URL aus baseUrl + path + queryItems.
    ///
    /// Designentscheidung:
    /// - Falls baseUrl bereits einen Pfad enthält (z.B. "/api"),
    ///   wird dieser überschrieben, damit wir nicht “/api/api/...” erzeugen.
    private func buildURL(path: String, queryItems: [URLQueryItem]?) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw PortalApiError.invalidBaseUrl
        }

        // Pfad bewusst überschreiben
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PortalApiError.invalidURL
        }
        return url
    }

    /// Führt einen GET-Request aus, prüft Statuscode und decoded JSON als T.
    private func performRequest<T: Decodable>(url: URL, decodeAs type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Request ausführen (async)
        let (data, response) = try await URLSession.shared.data(for: request)

        // HTTP Response validieren
        guard let http = response as? HTTPURLResponse else {
            throw PortalApiError.noHTTPResponse
        }

        // Debug-Logging (hilfreich beim Entwickeln)
        print("📡 [PortalApiClient] Request:", url.absoluteString)
        print("📡 Status:", http.statusCode)
        print("📡 Body:", String(data: data, encoding: .utf8) ?? "<non-UTF8 / empty>")

        // Fehlerstatuscodes inkl. Body weiterreichen
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PortalApiError.httpError(status: http.statusCode, body: body)
        }

        // Leerer Body ist selten – beim Feed können wir dann “leer” zurückgeben.
        if data.isEmpty {
            if T.self == PortalTrackListResponse.self {
                let empty = PortalTrackListResponse(trackCount: 0, tracks: [])
                return empty as! T
            }
            throw PortalApiError.httpError(
                status: http.statusCode,
                body: "Leerer Response-Body bei erwarteten Daten."
            )
        }

        // JSON decode
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return try decoder.decode(T.self, from: data)
    }
}
