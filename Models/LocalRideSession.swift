import Foundation
import CoreLocation

/// Komplette Fahrt-Session mit Track und Events
struct LocalRideSession: Codable, Identifiable {
    static let formatVersion = "1.0"

    let formatVersion: String
    let id: UUID
    let createdAt: Date
    var modifiedAt: Date

    // Metadaten
    let appVersion: String
    let deviceModel: String
    let handlebarWidthCm: Int

    // Upload-Status
    var uploadedAt: Date?

    // Track-Punkte (GPS-Verlauf)
    var trackPoints: [TrackPoint]

    // Überholvorgänge
    var events: [LocalOvertakeEvent]

    /// Initialisierung für neue Session
    init(handlebarWidthCm: Int) {
        self.formatVersion = Self.formatVersion
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.deviceModel = Self.deviceModelName()
        self.handlebarWidthCm = handlebarWidthCm
        self.uploadedAt = nil
        self.trackPoints = []
        self.events = []
    }

    /// Ob die Fahrt bereits hochgeladen wurde
    var isUploaded: Bool {
        uploadedAt != nil
    }

    /// Gesamtstrecke in Metern
    var totalDistanceMeters: Double {
        guard trackPoints.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<trackPoints.count {
            let prev = CLLocation(latitude: trackPoints[i-1].latitude,
                                  longitude: trackPoints[i-1].longitude)
            let curr = CLLocation(latitude: trackPoints[i].latitude,
                                  longitude: trackPoints[i].longitude)
            total += curr.distance(from: prev)
        }
        return total
    }

    /// Anzahl bewerteter Events
    var ratedEventsCount: Int {
        events.filter { $0.threatLevel != nil }.count
    }

    /// Fahrtdauer in Sekunden
    var durationSeconds: TimeInterval? {
        guard let first = trackPoints.first?.timestamp,
              let last = trackPoints.last?.timestamp else { return nil }
        return last.timeIntervalSince(first)
    }

    private static func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

/// Einzelner Track-Punkt
struct TrackPoint: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let speed: Double?       // m/s
    let course: Double?      // Kurs in Grad (0-360, 0=Nord)
    let accuracy: Double?    // Horizontal Accuracy in Metern

    init(location: CLLocation) {
        self.timestamp = location.timestamp
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.speed = location.speed >= 0 ? location.speed : nil
        self.course = location.course >= 0 ? location.course : nil
        self.accuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
    }
}
