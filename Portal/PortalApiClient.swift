// SPDX-License-Identifier: GPL-3.0-or-later

// PortalApiClient.swift

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
        case isPublic = "public"
    }

    // ✅ Tolerantes Decoding: fehlende / null Felder führen nicht zum kompletten Decode-Fehler
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Pflichtfelder
        id = try c.decode(Int.self, forKey: .id)
        slug = try c.decode(String.self, forKey: .slug)

        // Optional
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)

        // Strings: tolerant
        createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        updatedAt = (try? c.decode(String.self, forKey: .updatedAt)) ?? ""
        processingStatus = (try? c.decode(String.self, forKey: .processingStatus)) ?? ""

        recordedAt = (try? c.decode(String.self, forKey: .recordedAt)) ?? ""
        recordedUntil = (try? c.decode(String.self, forKey: .recordedUntil)) ?? ""

        // Bools / Numbers: tolerant
        isPublic = (try? c.decode(Bool.self, forKey: .isPublic)) ?? false

        duration = (try? c.decode(Double.self, forKey: .duration)) ?? 0
        length = (try? c.decode(Double.self, forKey: .length)) ?? 0

        numEvents = (try? c.decode(Int.self, forKey: .numEvents)) ?? 0
        numValid = (try? c.decode(Int.self, forKey: .numValid)) ?? 0
        numMeasurements = (try? c.decode(Int.self, forKey: .numMeasurements)) ?? 0

        author = (try? c.decode(PortalAuthor.self, forKey: .author))
            ?? PortalAuthor(id: 0, displayName: "(unbekannt)", bio: nil, image: nil)
    }

    // ✅ Memberwise-Init für Preview/Tests
    init(
        id: Int,
        slug: String,
        title: String?,
        description: String?,
        createdAt: String,
        updatedAt: String,
        isPublic: Bool,
        processingStatus: String,
        recordedAt: String,
        recordedUntil: String,
        duration: Double,
        length: Double,
        numEvents: Int,
        numValid: Int,
        numMeasurements: Int,
        author: PortalAuthor
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPublic = isPublic
        self.processingStatus = processingStatus
        self.recordedAt = recordedAt
        self.recordedUntil = recordedUntil
        self.duration = duration
        self.length = length
        self.numEvents = numEvents
        self.numValid = numValid
        self.numMeasurements = numMeasurements
        self.author = author
    }
}

/// Response-Wrapper für Track-Listen (Feed)
struct PortalTrackListResponse: Decodable {
    let trackCount: Int
    let tracks: [PortalTrackSummary]

    /// ✅ Anzahl Tracks, die beim Decoding übersprungen wurden (kaputt/unvollständig)
    let skippedTracksCount: Int

    enum CodingKeys: String, CodingKey {
        case trackCount
        case tracks
    }

    // ⚠️ Wichtig: weil wir gleich einen custom init(from:) haben,
    // brauchen wir diesen Initializer für deinen "empty response" Fall in performRequest()
    init(trackCount: Int, tracks: [PortalTrackSummary], skippedTracksCount: Int = 0) {
        self.trackCount = trackCount
        self.tracks = tracks
        self.skippedTracksCount = skippedTracksCount
    }

    // ✅ Lossy: wenn 1 Track kaputt ist, wird er übersprungen, der Rest bleibt sichtbar
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        trackCount = (try? c.decode(Int.self, forKey: .trackCount)) ?? 0

        if let lossy = try? c.decode(LossyArray<PortalTrackSummary>.self, forKey: .tracks) {
            tracks = lossy.elements
            skippedTracksCount = lossy.skippedCount
        } else {
            tracks = []
            skippedTracksCount = 0
        }
    }
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

final class PortalApiClient {

    private let baseUrl: String

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

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

    /// Lädt Detailinfos zu einem Track aus GET /api/tracks/<slug>
    func fetchTrackDetail(slug: String) async throws -> PortalTrackDetailResponse {
        let url = try buildURL(path: "/api/tracks/\(slug)", queryItems: nil)
        return try await performRequest(url: url, decodeAs: PortalTrackDetailResponse.self)
    }

    /// Lädt verarbeitete Track-Daten (Route + Events) aus GET /api/tracks/<slug>/data
    func fetchTrackData(slug: String) async throws -> PortalTrackData {
        let url = try buildURL(path: "/api/tracks/\(slug)/data", queryItems: nil)
        return try await performRequest(url: url, decodeAs: PortalTrackData.self)
    }

    /// Löscht einen Track via DELETE /api/tracks/<slug>
    /// Benötigt API-Key für Authentifizierung
    func deleteTrack(slug: String, apiKey: String) async throws {
        let url = try buildURL(path: "/api/tracks/\(slug)", queryItems: nil)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("OBSUserId \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw PortalApiError.noHTTPResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PortalApiError.httpError(status: http.statusCode, body: body)
        }
    }

    private func buildURL(path: String, queryItems: [URLQueryItem]?) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw PortalApiError.invalidBaseUrl
        }

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

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PortalApiError.httpError(status: http.statusCode, body: body)
        }

        if data.isEmpty {
            if let empty = PortalTrackListResponse(trackCount: 0, tracks: [], skippedTracksCount: 0) as? T {
                return empty
            }
            throw PortalApiError.httpError(
                status: http.statusCode,
                body: "Leerer Response-Body bei erwarteten Daten."
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return try decoder.decode(T.self, from: data)
    }
}
