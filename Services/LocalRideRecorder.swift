import Foundation
import CoreLocation

/// Thread-sicherer Recorder für lokale Fahrten mit Bewertungsmöglichkeit.
/// Schreibt parallel zur .bin-Datei eine .json-Datei mit Track und Events.
final class LocalRideRecorder {
    private let queue = DispatchQueue(label: "local.ride.recorder")
    private var currentSession: LocalRideSession?
    private(set) var fileURL: URL?

    private var trackPointCounter = 0
    private let saveEveryNPoints = 10  // Periodisches Speichern

    // MARK: - Session Lifecycle

    func startSession(handlebarWidthCm: Int) {
        queue.sync {
            let session = LocalRideSession(handlebarWidthCm: handlebarWidthCm)
            self.currentSession = session

            let url = createFileURL(for: session.createdAt)
            self.fileURL = url
            self.trackPointCounter = 0

            saveSession()
            print("LocalRideRecorder: Session gestartet → \(url.lastPathComponent)")
        }
    }

    func finishSession() {
        queue.sync {
            guard currentSession != nil else { return }
            currentSession?.modifiedAt = Date()
            saveSession()

            if let url = fileURL {
                print("LocalRideRecorder: Session beendet → \(url.lastPathComponent) (\(currentSession?.trackPoints.count ?? 0) Punkte, \(currentSession?.events.count ?? 0) Events)")
            }

            currentSession = nil
            fileURL = nil
        }
    }

    var isRecording: Bool {
        queue.sync { currentSession != nil }
    }

    // MARK: - Recording

    func recordTrackPoint(_ location: CLLocation) {
        queue.async {
            guard self.currentSession != nil else { return }

            let point = TrackPoint(location: location)
            self.currentSession?.trackPoints.append(point)

            self.trackPointCounter += 1
            if self.trackPointCounter >= self.saveEveryNPoints {
                self.saveSession()
                self.trackPointCounter = 0
            }
        }
    }

    func recordOvertakeEvent(coordinate: CLLocationCoordinate2D, distanceCm: Int,
                             distanceStationaryCm: Int?, speed: Double?, course: Double?) {
        queue.async {
            guard self.currentSession != nil else { return }

            let event = LocalOvertakeEvent(
                timestamp: Date(),
                coordinate: coordinate,
                distanceCm: distanceCm,
                distanceStationaryCm: distanceStationaryCm,
                speed: speed,
                course: course
            )
            self.currentSession?.events.append(event)
            self.saveSession()

            print("LocalRideRecorder: Event aufgezeichnet → \(distanceCm) cm (rechts: \(distanceStationaryCm ?? -1) cm)")
        }
    }

    // MARK: - File Operations

    private func createFileURL(for date: Date) -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("OBS/rides", isDirectory: true)

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: date)

        return dir.appendingPathComponent("ride_\(stamp).json")
    }

    private func saveSession() {
        guard let session = currentSession, let url = fileURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            print("LocalRideRecorder: Speicherfehler → \(error.localizedDescription)")
        }
    }
}
