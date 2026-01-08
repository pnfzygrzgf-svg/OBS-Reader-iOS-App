// ClassicCsvRecorder.swift

import Foundation
import CoreLocation

/// Recorder für OBS Classic, der direkt eine CSV-Datei im OBS-Format schreibt.
///
/// Grundidee:
/// - Eine Session = eine CSV-Datei.
/// - Pro Messung eine Zeile (Measurements = 1).
/// - File-I/O läuft über eine eigene Queue, damit Bluetooth/UI nicht blockieren.
final class ClassicCsvRecorder {

    // =====================================================
    // MARK: - Public
    // =====================================================

    /// URL der aktuell offenen CSV-Datei (falls vorhanden).
    /// - Wird in `startSession()` gesetzt und in `finishSession()`/Fehlerfall wieder freigegeben.
    private(set) var fileURL: URL?

    // =====================================================
    // MARK: - Private
    // =====================================================

    /// Serialisiert File-I/O auf eine eigene Queue, damit es:
    /// - thread-safe ist (FileHandle nicht parallel beschrieben wird)
    /// - UI/BT Threads nicht blockiert
    private let queue = DispatchQueue(label: "obs.classic.csv.writer")

    /// Aktives FileHandle der CSV-Datei (nur während einer Session gesetzt).
    private var handle: FileHandle?

    /// Abstand Lenkerende → Radmitte (pro Seite) in cm, z.B. 30 cm.
    /// Wird vom Rohwert abgezogen, um den “korrigierten Abstand” zu erhalten.
    private let handlebarOffsetCm: Int

    /// Firmware-Version des OBS Classic (optional, wird in Metadaten geschrieben).
    private let firmwareVersion: String?

    /// App-Version (z.B. "1.0.0"), wird u. a. in deviceId verwendet.
    private let appVersion: String

    /// DeviceId in Metadaten (hier: "obs-ios-<appVersion>").
    private let deviceId: String

    /// Faktor für Umrechnung distance(cm) → FlightTime(µs).
    /// (OBS rechnet mit einer linearen Näherung; hier wie in Referenz-Implementationen)
    private let factor: Double = 58.0

    /// Anzahl Messungen pro CSV-Zeile.
    /// In diesem Recorder: genau eine Messung pro Zeile.
    private let maxMeasurementsPerLine = 1

    // =====================================================
    // MARK: - Init
    // =====================================================

    /// Initialisiert den Recorder mit den benötigten Metadaten.
    ///
    /// - Parameters:
    ///   - handlebarOffsetCm: Abstand je Lenkerseite zur Radmitte (z.B. 30 cm).
    ///     Dieser Wert wird später von den Rohwerten abgezogen, um korrigierte Werte zu erhalten.
    ///   - appVersion: App-Version (z.B. "1.0.0") – wird in Metadaten/DeviceId geschrieben.
    ///   - firmwareVersion: Firmware des OBS Classic (optional) – wird in Metadaten geschrieben.
    init(handlebarOffsetCm: Int, appVersion: String, firmwareVersion: String?) {
        self.handlebarOffsetCm = handlebarOffsetCm
        self.appVersion = appVersion
        self.firmwareVersion = firmwareVersion

        // Eindeutige ID für Metadaten/Uploads (hier simpel aus App-Version abgeleitet).
        self.deviceId = "obs-ios-\(appVersion)"
    }

    // =====================================================
    // MARK: - Lifecycle
    // =====================================================

    /// Startet eine neue CSV-Session:
    /// - legt Datei an
    /// - öffnet FileHandle
    /// - schreibt Metadatenzeile (Key=Value&Key=Value…)
    /// - schreibt CSV-Headerzeile
    ///
    /// Hinweis: `queue.sync` stellt sicher, dass nach Rückkehr aus der Funktion
    /// wirklich schon eine offene Datei existiert (damit anschließend sofort geschrieben werden kann).
    func startSession() {
        queue.sync {
            do {
                let fm = FileManager.default

                // Documents-Verzeichnis der App (sandboxed).
                let docs = try fm.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )

                // Zielordner: Documents/OBS
                let dir = docs.appendingPathComponent("OBS", isDirectory: true)
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }

                // Dateiname: fahrt_YYYYMMDD_HHmmss.csv
                // en_US_POSIX verhindert Locale-bedingte Formatierungsprobleme.
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let stamp = formatter.string(from: Date())

                let file = dir.appendingPathComponent("fahrt_\(stamp).csv")

                // Datei anlegen (leer)
                fm.createFile(atPath: file.path, contents: nil)

                // FileHandle zum Schreiben öffnen
                let fh = try FileHandle(forWritingTo: file)
                self.handle = fh
                self.fileURL = file

                // Metadaten + Header vorbereiten
                let metadataLine = genMetadataLine()
                let headerLine = genCSVHeader(maxMeasurements: maxMeasurementsPerLine)

                // Zeilen schreiben (jeweils mit newline)
                try fh.write(contentsOf: (metadataLine + "\n").data(using: .utf8)!)
                try fh.write(contentsOf: (headerLine + "\n").data(using: .utf8)!)

                print("ClassicCsvRecorder: startSession -> \(file.path)")
            } catch {
                // Fehler: alles zurücksetzen, damit der Recorder in sauberem Zustand bleibt
                print("ClassicCsvRecorder: startSession error: \(error)")
                self.handle = nil
                self.fileURL = nil
            }
        }
    }

    /// Beendet die Session:
    /// - synchronisiert den FileBuffer (flush)
    /// - schließt das FileHandle
    ///
    /// Hinweis: auch hier `queue.sync`, damit beim Return garantiert geschlossen ist.
    func finishSession() {
        queue.sync {
            guard let handle = self.handle else { return }

            // synchronize() versucht gepufferte Daten zu flushen
            do {
                try handle.synchronize()
            } catch {
                print("ClassicCsvRecorder: synchronize error: \(error)")
            }

            // handle schließen (wichtig, damit Datei sauber abgeschlossen wird)
            do {
                try handle.close()
            } catch {
                print("ClassicCsvRecorder: close error: \(error)")
            }

            self.handle = nil
            print("ClassicCsvRecorder: finishSession -> \(fileURL?.lastPathComponent ?? "-")")
        }
    }

    // =====================================================
    // MARK: - Schreiben von Messungen
    // =====================================================

    /// Schreibt eine einzelne Messung als CSV-Zeile.
    ///
    /// Ablauf:
    /// 1) Validieren, dass eine Session aktiv ist (`handle != nil`)
    /// 2) Zeile generieren (inkl. Korrektur, GPS-Felder, Flags)
    /// 3) Zeile als UTF-8 ans Dateiende schreiben
    ///
    /// - Parameters:
    ///   - leftCm: Rohwert linker Abstand in cm (ohne Lenkerkorrektur), oder nil
    ///   - rightCm: Rohwert rechter Abstand in cm (ohne Lenkerkorrektur), oder nil
    ///   - confirmed: true, wenn diese Messung per Button als „Überholvorgang“ bestätigt wurde
    ///   - location: letzte bekannte Position (optional)
    ///   - batteryVoltage: Batteriespannung in Volt (optional; nil => Spalte bleibt leer)
    func recordMeasurement(
        leftCm: UInt16?,
        rightCm: UInt16?,
        confirmed: Bool,
        location: CLLocation?,
        batteryVoltage: Double?
    ) {
        // async: Messungen blockieren den Aufrufer nicht (Bluetooth/UI Thread bleibt frei).
        queue.async {
            guard let handle = self.handle else {
                // Wenn keine Session offen ist, kann nicht geschrieben werden.
                print("ClassicCsvRecorder: recordMeasurement ohne offene Session")
                return
            }

            // Zeitstempel der Messung
            let now = Date()

            // CSV Zeile erzeugen (Semikolon-getrennt)
            let line = self.genCSVRow(
                date: now,
                location: location,
                batteryVoltage: batteryVoltage,
                leftCm: leftCm,
                rightCm: rightCm,
                confirmed: confirmed
            )

            // Zeile als UTF-8 schreiben
            if let data = (line + "\n").data(using: .utf8) {
                do {
                    try handle.write(contentsOf: data)
                } catch {
                    print("ClassicCsvRecorder: write error: \(error)")
                }
            }
        }
    }

    // =====================================================
    // MARK: - Metadata / Header
    // =====================================================

    /// Generiert die erste Metadatenzeile.
    ///
    /// Format: URL-ähnliche Key-Value-Paare, getrennt mit `&`
    /// Beispiel: "Key=Value&Key2=Value2"
    ///
    /// Diese Metadaten werden von OBS-Tools/Uploadern genutzt, um die CSV korrekt zu interpretieren.
    private func genMetadataLine() -> String {
        // Angelehnt an die Flutter-App / UploadManager.dart (_genMetadataHeader)
        let fields = [
            // Firmware kann fehlen → "unknown"
            "OBSFirmwareVersion=\(firmwareVersion ?? "unknown")",

            // OBSDataFormat=2 ist “CSV Format Version” (nach OBS-Konvention)
            "OBSDataFormat=2",

            // DataPerMeasurement=3 korrespondiert zu Tms/Lus/Rus
            "DataPerMeasurement=3",

            // Wir schreiben genau 1 Messung pro Zeile
            "MaximumMeasurementsPerLine=\(maxMeasurementsPerLine)",

            // Lenkeroffset links/rechts in cm (Korrektur des Rohwerts)
            "OffsetLeft=\(handlebarOffsetCm)",
            "OffsetRight=\(handlebarOffsetCm)",

            // Privacy-Areas (hier nicht genutzt)
            "NumberOfDefinedPrivacyAreas=0",
            "PrivacyLevelApplied=AbsolutePrivacy",

            // Maximal gültige Flugzeit (µs) laut Spezifikation/Referenz
            "MaximumValidFlightTimeMicroseconds=18560",

            // Sensor-Info (Textfeld)
            "DistanceSensorsUsed=HC-SR04/JSN-SR04T",

            // DeviceId zur Identifikation des Upload-Clients
            "DeviceId=\(deviceId)",

            // CSV Zeitzone ist UTC (im Datenteil verwenden wir ebenfalls UTC)
            "TimeZone=UTC"
        ]
        return fields.joined(separator: "&")
    }

    /// CSV-Headerzeile entsprechend der OBS-Spezifikation.
    /// Trennzeichen ist `;` (typisch im deutschsprachigen CSV-Kontext).
    ///
    /// Wichtig: Die Reihenfolge muss zum späteren `genCSVRow()` passen.
    private func genCSVHeader(maxMeasurements: Int) -> String {
        var fields: [String] = [
            // Zeitangaben
            "Date",
            "Time",
            "Millis",

            // Freitext
            "Comment",

            // GPS / Bewegung
            "Latitude",
            "Longitude",
            "Altitude",
            "Course",
            "Speed",
            "HDOP",
            "Satellites",

            // Batterie (hier Voltage, je nach Konvention)
            "BatteryLevel",

            // Korrigierte Abstände in cm
            "Left",
            "Right",

            // Event/Status
            "Confirmed",
            "Marked",
            "Invalid",
            "InsidePrivacyArea",

            // FlightTime-Faktor und Messungsanzahl
            "Factor",
            "Measurements"
        ]

        // Für jede Messung: Zeitoffset (Tms) und FlightTimes (Lus/Rus)
        for i in 1...maxMeasurements {
            fields.append("Tms\(i)")
            fields.append("Lus\(i)")
            fields.append("Rus\(i)")
        }

        return fields.joined(separator: ";")
    }

    // =====================================================
    // MARK: - CSV-Zeile für eine Messung
    // =====================================================

    /// Baut eine vollständige CSV-Datenzeile für genau eine Messung.
    ///
    /// Inhalt:
    /// - Datum/Zeit in UTC (Date/Time + Millis)
    /// - Optional GPS-Felder (sonst leer)
    /// - Optional Batterie (sonst leer)
    /// - Left/Right (korrigiert um handlebarOffsetCm)
    /// - Flags (Confirmed/Marked/Invalid/InsidePrivacyArea)
    /// - Tms1/Lus1/Rus1 (FlightTimes auf Basis *Rohwert* in cm)
    private func genCSVRow(
        date: Date,
        location: CLLocation?,
        batteryVoltage: Double?,
        leftCm: UInt16?,
        rightCm: UInt16?,
        confirmed: Bool
    ) -> String {

        // --- Datum/Zeit in UTC ---
        // OBS CSV nutzt typischerweise dd.MM.yyyy und HH:mm:ss.
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.locale = Locale(identifier: "de_DE")
        dateFormatter.dateFormat = "dd.MM.yyyy"

        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        timeFormatter.locale = Locale(identifier: "de_DE")
        timeFormatter.dateFormat = "HH:mm:ss"

        let dateStr = dateFormatter.string(from: date)
        let timeStr = timeFormatter.string(from: date)

        // Millis seit Unix epoch (UTC), wie im Header vorgesehen
        let millis = Int64(date.timeIntervalSince1970 * 1000.0)

        // --- GPS / Bewegung ---
        // Falls keine Location vorhanden ist: Felder leer lassen.
        let latStr: String
        let lonStr: String
        let altStr: String
        let courseStr: String
        let speedStr: String
        let hdopStr: String
        let satsStr: String

        if let loc = location {
            latStr = String(loc.coordinate.latitude)
            lonStr = String(loc.coordinate.longitude)
            altStr = String(loc.altitude)

            // course: Richtung über Grund in Grad, -1 falls unbekannt
            courseStr = loc.course >= 0 ? String(loc.course) : ""

            // speed: iOS liefert m/s, -1 falls unbekannt
            // Kommentar im Code: Spezifikation sagt km/h, aber wie in Flutter-App wird m/s genutzt.
            speedStr = loc.speed >= 0 ? String(loc.speed) : ""

            // horizontalAccuracy dient hier als HDOP-ähnlicher Wert
            hdopStr = String(loc.horizontalAccuracy)

            // iOS liefert Satellitenanzahl nicht direkt → leer
            satsStr = ""
        } else {
            latStr = ""
            lonStr = ""
            altStr = ""
            courseStr = ""
            speedStr = ""
            hdopStr = ""
            satsStr = ""
        }

        // Batterie optional, sonst leer
        let batteryStr: String = batteryVoltage.map { String($0) } ?? ""

        // --- Abstände korrigieren (für CSV Left/Right) ---
        // Korrigiert = raw(cm) - handlebarOffsetCm, nicht < 0
        // (handlebarOffsetCm entspricht "halbe Lenkerbreite" pro Seite)
        let leftCorrected: Int? = leftCm.map { max(Int($0) - handlebarOffsetCm, 0) }
        let rightCorrected: Int? = rightCm.map { max(Int($0) - handlebarOffsetCm, 0) }

        let leftCorrectedStr = leftCorrected.map { String($0) } ?? ""
        let rightCorrectedStr = rightCorrected.map { String($0) } ?? ""

        // --- Flags/Marker ---
        // Confirmed = 1 wenn Button-Press / bestätigtes Überholen, sonst 0
        let confirmedStr = confirmed ? "1" : "0"

        // Bei bestätigtem Button-Event markieren wir das Feld “Marked”
        // (String wird von manchen Tools als Ereignislabel genutzt)
        let markedStr = confirmed ? "OVERTAKING" : ""

        // Aktuell keine Invalid/Privacy-Logik implementiert → 0
        let invalidStr = "0"
        let insidePrivacyAreaStr = "0"

        // Factor und Measurements-Felder
        let factorStr = String(factor)
        let measurementsStr = "1" // exakt eine Messung pro Zeile

        // --- Tms/Lus/Rus für Messung 1 ---
        // Tms1: Zeitoffset innerhalb dieser Zeile/Serie.
        // Da wir 1 Messung/Zeitpunkt pro Zeile haben: 0.
        let tms1Str = "0"

        // Lus1/Rus1: FlightTime (µs) = raw distance (cm) * factor
        // Wichtig: Hier wird *der Rohwert* verwendet, nicht der korrigierte.
        // (OBS-Referenzdaten nutzen häufig Rohwerte für FlightTimes und getrennt davon korrigierte cm-Werte.)
        let lus1Str: String
        if let leftCm {
            let us = Int(Double(leftCm) * factor)
            lus1Str = String(us)
        } else {
            lus1Str = ""
        }

        let rus1Str: String
        if let rightCm {
            let us = Int(Double(rightCm) * factor)
            rus1Str = String(us)
        } else {
            rus1Str = ""
        }

        // Freitextkommentar pro Zeile (kann in Tools angezeigt werden)
        let commentStr = "Recorded via OBS iOS Classic"

        // Alle Felder in der exakten Reihenfolge des Headers zusammenbauen
        let fields: [String] = [
            dateStr,
            timeStr,
            String(millis),
            commentStr,
            latStr,
            lonStr,
            altStr,
            courseStr,
            speedStr,
            hdopStr,
            satsStr,
            batteryStr,
            leftCorrectedStr,
            rightCorrectedStr,
            confirmedStr,
            markedStr,
            invalidStr,
            insidePrivacyAreaStr,
            factorStr,
            measurementsStr,
            tms1Str,
            lus1Str,
            rus1Str
        ]

        // Semikolon als Trenner
        return fields.joined(separator: ";")
    }
}
