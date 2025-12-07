import Foundation
import CoreLocation

final class OBSRecorder {

    private let binWriter = OBSFileWriter()
    // CSV-Writer entfernt – es werden keine CSV-Dateien mehr erzeugt

    private(set) var isRecording = false

    func start() {
        guard !isRecording else { return }
        isRecording = true

        binWriter.startSession()
        // Keine CSV-Session mehr
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false

        binWriter.finishSession()
        // Keine CSV-Session mehr
    }

    /// vom LocationManager weiterreichen
    /// (aktuell ohne Funktion, da keine CSVs mehr geschrieben werden)
    func updateLocation(_ location: CLLocation) {
        // Früher: csvWriter.updateLocation(location)
        // Jetzt: keine Aktion nötig, BIN-Logging läuft über andere Stellen
    }

    /// immer dann aufrufen, wenn du ein neues OBS-Event bekommen hast
    func handleMeasurement(
        rawCOBSFrame: Data,
        timestamp: Date,
        leftCm: Int?,
        rightCm: Int?,
        comment: String? = nil
    ) {
        guard isRecording else { return }

        // .bin
        binWriter.write(rawCOBSFrame)

        // Früher: zusätzlich CSV-Zeile schreiben
        // csvWriter.appendMeasurement(...)
        // Jetzt: keine CSV-Ausgabe mehr
    }
}
