import Foundation
import Combine

/// Store für lokale Fahrten mit Bewertungsfunktion.
/// Lädt, speichert und verwaltet LocalRideSession-Dateien.
final class LocalRideStore: ObservableObject {
    @Published var rides: [LocalRideSession] = []
    @Published var isLoading = false

    private let ridesDirectory: URL
    private let queue = DispatchQueue(label: "local.ride.store")

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        ridesDirectory = docs.appendingPathComponent("OBS/rides", isDirectory: true)
    }

    // MARK: - Load

    func loadRides() {
        isLoading = true

        queue.async { [weak self] in
            guard let self = self else { return }

            let fm = FileManager.default

            // Verzeichnis erstellen falls nicht vorhanden
            if !fm.fileExists(atPath: self.ridesDirectory.path) {
                try? fm.createDirectory(at: self.ridesDirectory, withIntermediateDirectories: true)
            }

            guard let files = try? fm.contentsOfDirectory(
                at: self.ridesDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else {
                DispatchQueue.main.async {
                    self.rides = []
                    self.isLoading = false
                }
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let loadedRides = files
                .filter { $0.pathExtension == "json" }
                .compactMap { url -> LocalRideSession? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? decoder.decode(LocalRideSession.self, from: data)
                }
                .sorted { $0.createdAt > $1.createdAt }

            DispatchQueue.main.async {
                self.rides = loadedRides
                self.isLoading = false
            }
        }
    }

    // MARK: - Update Event Rating

    func updateEventRating(rideId: UUID, eventId: UUID, threatLevel: ThreatLevel?) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Ride in der Liste finden
            guard let rideIndex = self.rides.firstIndex(where: { $0.id == rideId }) else { return }

            // Event im Ride finden
            guard let eventIndex = self.rides[rideIndex].events.firstIndex(where: { $0.id == eventId }) else { return }

            // Update durchführen
            var updatedRide = self.rides[rideIndex]
            updatedRide.events[eventIndex].threatLevel = threatLevel
            updatedRide.modifiedAt = Date()

            // Speichern
            self.saveRide(updatedRide)

            // UI aktualisieren
            DispatchQueue.main.async {
                self.rides[rideIndex] = updatedRide
            }
        }
    }

    // MARK: - Mark as Uploaded

    func markAsUploaded(rideId: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }

            guard let rideIndex = self.rides.firstIndex(where: { $0.id == rideId }) else { return }

            var updatedRide = self.rides[rideIndex]
            updatedRide.uploadedAt = Date()
            updatedRide.modifiedAt = Date()

            self.saveRide(updatedRide)

            DispatchQueue.main.async {
                self.rides[rideIndex] = updatedRide
            }
        }
    }

    // MARK: - Delete

    func deleteRide(_ ride: LocalRideSession) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Datei finden und löschen
            let url = self.fileURL(for: ride)
            try? FileManager.default.removeItem(at: url)

            // Aus Liste entfernen
            DispatchQueue.main.async {
                self.rides.removeAll { $0.id == ride.id }
            }
        }
    }

    // MARK: - Export

    /// Exportiert eine Fahrt als GeoJSON für Portal-Kompatibilität
    /// - Parameters:
    ///   - ride: Die zu exportierende Fahrt
    ///   - includeRatings: Ob Bedrohungsbewertungen eingeschlossen werden sollen (Standard: true)
    func exportAsGeoJSON(_ ride: LocalRideSession, includeRatings: Bool = true) -> Data? {
        var features: [[String: Any]] = []

        for event in ride.events {
            var properties: [String: Any] = [
                "distance_overtaker": Double(event.distanceCm) / 100.0,
                "distance_cm": event.distanceCm,
                "time": ISO8601DateFormatter().string(from: event.timestamp)
            ]

            // Rechter Sensor (stationär)
            if let stationaryCm = event.distanceStationaryCm {
                properties["distance_stationary"] = Double(stationaryCm) / 100.0
                properties["distance_stationary_cm"] = stationaryCm
            }

            // Geschwindigkeit in m/s
            if let speed = event.speed {
                properties["speed"] = speed
            }

            // Kurs in Radiant (Portal-Format: CCW from East)
            if let course = event.course {
                // Umrechnung: Grad (0=Nord, CW) → Radiant (0=Ost, CCW)
                let courseRadians = (90.0 - course) * .pi / 180.0
                properties["course"] = courseRadians
            }

            if includeRatings, let level = event.threatLevel {
                properties["threat_level"] = level.rawValue
                properties["threat_label"] = level.displayName
            }

            let feature: [String: Any] = [
                "type": "Feature",
                "geometry": [
                    "type": "Point",
                    "coordinates": [event.longitude, event.latitude]
                ],
                "properties": properties
            ]
            features.append(feature)
        }

        // Track als LineString
        if !ride.trackPoints.isEmpty {
            let coordinates = ride.trackPoints.map { [$0.longitude, $0.latitude] }
            let trackFeature: [String: Any] = [
                "type": "Feature",
                "geometry": [
                    "type": "LineString",
                    "coordinates": coordinates
                ],
                "properties": [
                    "type": "track"
                ]
            ]
            features.insert(trackFeature, at: 0)
        }

        let geoJSON: [String: Any] = [
            "type": "FeatureCollection",
            "features": features,
            "metadata": [
                "formatVersion": ride.formatVersion,
                "appVersion": ride.appVersion,
                "deviceModel": ride.deviceModel,
                "createdAt": ISO8601DateFormatter().string(from: ride.createdAt),
                "modifiedAt": ISO8601DateFormatter().string(from: ride.modifiedAt),
                "handlebarWidthCm": ride.handlebarWidthCm,
                "totalEvents": ride.events.count,
                "ratedEvents": ride.ratedEventsCount
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: geoJSON, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Private

    private func fileURL(for ride: LocalRideSession) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: ride.createdAt)
        return ridesDirectory.appendingPathComponent("ride_\(stamp).json")
    }

    private func saveRide(_ ride: LocalRideSession) {
        let url = fileURL(for: ride)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ride)
            try data.write(to: url, options: .atomic)
        } catch {
            print("LocalRideStore: Speicherfehler → \(error.localizedDescription)")
        }
    }
}
