// OBSRecorder.swift

import Foundation
import CoreLocation

/// Verantwortlich für das Starten/Stoppen einer Aufnahmesession
/// und das Schreiben von **bereits COBS-kodierten** OBS-Frames in eine .bin-Datei.
///
/// Wichtige Punkte:
/// - Nutzt intern `OBSFileWriter` zum Filehandling.
/// - Hat einen einfachen `isRecording`-Status.
/// - CSV-Unterstützung wurde entfernt; nur noch BIN-Logging.
/// - Die eigentliche Protobuf/COBS-Erzeugung passiert **außerhalb** dieser Klasse.
final class OBSRecorder {

    /// Schreibt die Frames in eine .bin-Datei (COBS + 0x00-Delimiter erwartet).
    private let binWriter = OBSFileWriter()
    // CSV-Writer entfernt – es werden keine CSV-Dateien mehr erzeugt

    /// Aktueller Aufnahmezustand (nur lokal, kein @Published).
    /// Kann z. B. vom aufrufenden Code abgefragt werden.
    private(set) var isRecording = false

    /// Startet eine neue Aufnahmesession.
    ///
    /// - Öffnet über `OBSFileWriter.startSession()` eine neue BIN-Datei.
    /// - Ignoriert den Aufruf, wenn bereits eine Aufnahme läuft.
    func start() {
        guard !isRecording else { return }
        isRecording = true

        binWriter.startSession()
        // Keine CSV-Session mehr
    }

    /// Beendet die laufende Aufnahmesession.
    ///
    /// - Flusht und schließt die aktuell geöffnete BIN-Datei.
    /// - Ignoriert den Aufruf, wenn gerade keine Aufnahme läuft.
    func stop() {
        guard isRecording else { return }
        isRecording = false

        binWriter.finishSession()
        // Keine CSV-Session mehr
    }

    /// Vom LocationManager weiterreichen.
    ///
    /// Aktuell ohne Funktion – historischer Rest:
    /// - Früher wurden hier CSV-Geopunkte geschrieben.
    /// - Das BIN-Logging für GPS findet jetzt an anderer Stelle statt
    ///   (z. B. direkt im `BluetoothManager.handleLocationUpdate(_:)`).
    func updateLocation(_ location: CLLocation) {
        // Früher: csvWriter.updateLocation(location)
        // Jetzt: keine Aktion nötig, BIN-Logging läuft über andere Stellen
    }

    /// Immer dann aufrufen, wenn du ein neues OBS-Event (als COBS-Frame) bekommen hast.
    ///
    /// - `rawCOBSFrame`:
    ///    Der komplette, bereits COBS-kodierte Frame inkl. 0x00-Delimiter, wie er
    ///    direkt ins .bin geschrieben werden soll.
    /// - `timestamp`, `leftCm`, `rightCm`, `comment`:
    ///    Historische Parameter für CSV-Logging – aktuell nur noch im API vorhanden,
    ///    aber ohne Verwendung.
    ///
    /// Wichtig:
    /// - Diese Methode prüft `isRecording`.
    /// - Die Protobuf-Serialisierung + COBS-Encoding muss vorher erfolgt sein.
    func handleMeasurement(
        rawCOBSFrame: Data,
        timestamp: Date,
        leftCm: Int?,
        rightCm: Int?,
        comment: String? = nil
    ) {
        guard isRecording else { return }

        // .bin: rohen COBS-Frame unverändert weiterreichen
        binWriter.write(rawCOBSFrame)

        // Früher: zusätzlich CSV-Zeile schreiben
        // csvWriter.appendMeasurement(...)
        // Jetzt: keine CSV-Ausgabe mehr
    }
}
