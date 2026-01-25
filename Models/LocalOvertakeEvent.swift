import Foundation
import CoreLocation

/// Einzelner Überholvorgang mit optionaler Bedrohungsbewertung
struct LocalOvertakeEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let distanceCm: Int                    // Linker Sensor (Überholer)
    let distanceStationaryCm: Int?         // Rechter Sensor (stationär)
    let speed: Double?                     // Geschwindigkeit in m/s
    let course: Double?                    // Kurs in Grad (0-360, 0=Nord)
    var threatLevel: ThreatLevel?

    /// CLLocationCoordinate2D für MapKit-Integration
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Initialisierung während der Aufnahme (ohne Bewertung)
    init(timestamp: Date, coordinate: CLLocationCoordinate2D, distanceCm: Int,
         distanceStationaryCm: Int?, speed: Double?, course: Double?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.distanceCm = distanceCm
        self.distanceStationaryCm = distanceStationaryCm
        self.speed = speed
        self.course = course
        self.threatLevel = nil
    }

    /// Vollständige Initialisierung (für Deserialisierung)
    init(id: UUID, timestamp: Date, latitude: Double, longitude: Double,
         distanceCm: Int, distanceStationaryCm: Int?, speed: Double?, course: Double?,
         threatLevel: ThreatLevel?) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.distanceCm = distanceCm
        self.distanceStationaryCm = distanceStationaryCm
        self.speed = speed
        self.course = course
        self.threatLevel = threatLevel
    }
}
