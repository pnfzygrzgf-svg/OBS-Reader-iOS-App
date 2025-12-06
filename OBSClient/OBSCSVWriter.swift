import Foundation
import CoreLocation

/// Schreibt eine einfache OBS-CSV-Datei im Stil der Beispiele
/// (empty-metadata.csv / gps-time.csv / zero-zero-bug.csv),
/// mit einem Eintrag pro Messzeile.
///
/// Ziel: Minimal lauffähiges CSV-Format, in das man Timestamp,
/// GPS und linke/rechte Abstände schreiben kann.
final class OBSCSVWriter {

    private let queue = DispatchQueue(label: "obs.csv.writer")

    private(set) var fileURL: URL?
    private var handle: FileHandle?

    // Letzte bekannte GPS-Daten (kannst du von außen setzen)
    private var lastLatitude: Double?
    private var lastLongitude: Double?
    private var lastAltitude: Double?
    private var lastSpeed: Double?
    private var lastHdop: Double?

    // Formatter für Datum/Zeit
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter

    init() {
        // dd.MM.yyyy (wie in deinen Beispielen)
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy"
        df.locale = Locale(identifier: "de_DE")
        df.timeZone = TimeZone(secondsFromGMT: 0) // GPS/UTC-ähnlich
        self.dateFormatter = df

        // HH:mm:ss
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        tf.locale = Locale(identifier: "de_DE")
        tf.timeZone = TimeZone(secondsFromGMT: 0)
        self.timeFormatter = tf
    }

    // MARK: - Session API

    /// Startet eine neue CSV-Session. Schließt ggf. eine alte zuerst.
    func startSession() {
        queue.sync {
            closeIfNeeded()

            do {
                let fm = FileManager.default

                // Documents/OBS
                let docs = try fm.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let dir = docs.appendingPathComponent("OBS", isDirectory: true)

                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }

                // fahrt_YYYYMMdd_HHmmss.csv
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let stamp = formatter.string(from: Date())

                let file = dir.appendingPathComponent("fahrt_\(stamp).csv")
                fm.createFile(atPath: file.path, contents: nil)

                let fh = try FileHandle(forWritingTo: file)
                self.handle = fh
                self.fileURL = file

                // Metadaten-Zeile (minimal, wie empty-metadata.csv)
                // Du kannst das bei Bedarf später erweitern.
                let meta = "OBSDataFormat=2\n"
                try fh.write(contentsOf: Data(meta.utf8))

                // Header-Zeile wie in deinen Beispielen (bis Rus30)
                let header = """
Date;Time;Millis;Comment;Latitude;Longitude;Altitude;Course;Speed;HDOP;Satellites;BatteryLevel;Left;Right;Confirmed;Marked;Invalid;InsidePrivacyArea;Factor;Measurements;Tms1;Lus1;Rus1;Tms2;Lus2;Rus2;Tms3;Lus3;Rus3;Tms4;Lus4;Rus4;Tms5;Lus5;Rus5;Tms6;Lus6;Rus6;Tms7;Lus7;Rus7;Tms8;Lus8;Rus8;Tms9;Lus9;Rus9;Tms10;Lus10;Rus10;Tms11;Lus11;Rus11;Tms12;Lus12;Rus12;Tms13;Lus13;Rus13;Tms14;Lus14;Rus14;Tms15;Lus15;Rus15;Tms16;Lus16;Rus16;Tms17;Lus17;Rus17;Tms18;Lus18;Rus18;Tms19;Lus19;Rus19;Tms20;Lus20;Rus20;Tms21;Lus21;Rus21;Tms22;Lus22;Rus22;Tms23;Lus23;Rus23;Tms24;Lus24;Rus24;Tms25;Lus25;Rus25;Tms26;Lus26;Rus26;Tms27;Lus27;Rus27;Tms28;Lus28;Rus28;Tms29;Lus29;Rus29;Tms30;Lus30;Rus30\n
"""
                try fh.write(contentsOf: Data(header.utf8))

                print("OBSCSVWriter: startSession -> \(file.path)")
            } catch {
                print("OBSCSVWriter: startSession error: \(error)")
                self.handle = nil
                self.fileURL = nil
            }
        }
    }

    /// Aktualisiert die zuletzt bekannte GPS-Position.
    /// Kannst du z.B. aus deinem LocationManager aufrufen.
    func updateLocation(_ location: CLLocation) {
        queue.async {
            self.lastLatitude = location.coordinate.latitude
            self.lastLongitude = location.coordinate.longitude
            self.lastAltitude = location.altitude
            self.lastSpeed = max(location.speed, 0)  // m/s
            self.lastHdop = location.horizontalAccuracy  // semantisch nicht 1:1 HDOP, aber besser als nichts
        }
    }

    /// Fügt eine Messzeile hinzu.
    ///
    /// - Parameter timestamp: Zeitpunkt der Messung (z.B. Smartphone-Zeit aus Event.time)
    /// - leftCm / rightCm: Abstand in cm (mindestens einer der beiden nicht nil)
    ///
    /// Viele Felder (Satellites, BatteryLevel, Confirmed, Marked, Lus/Rus…) werden
    /// zunächst leer gelassen oder mit neutralen Defaults gefüllt. Das reicht für Tests
    /// und einfache Auswertung; für 100% Portal-Kompatibilität kann man es später verfeinern.
    func appendMeasurement(
        timestamp: Date,
        leftCm: Int?,
        rightCm: Int?,
        comment: String? = nil
    ) {
        queue.async {
            guard let handle = self.handle else {
                print("OBSCSVWriter: appendMeasurement() without open file")
                return
            }

            // Datum / Zeit / Millis
            let dateStr = self.dateFormatter.string(from: timestamp)
            let timeStr = self.timeFormatter.string(from: timestamp)

            let ts = timestamp.timeIntervalSince1970
            let millis = Int((ts - floor(ts)) * 1000.0)

            // GPS (falls vorhanden)
            let latStr = self.formatOptional(self.lastLatitude, decimals: 6)
            let lonStr = self.formatOptional(self.lastLongitude, decimals: 6)
            let altStr = self.formatOptional(self.lastAltitude, decimals: 1)
            // Course lassen wir leer ("")
            let speedStr = self.formatOptional(self.lastSpeed, decimals: 2)
            let hdopStr = self.formatOptional(self.lastHdop, decimals: 2)

            // Satellites, BatteryLevel lassen wir erstmal leer.
            let satellitesStr = ""
            let batteryStr = ""

            // Left / Right (in cm)
            let leftStr = leftCm.map { String($0) } ?? ""
            let rightStr = rightCm.map { String($0) } ?? ""

            // Confirmed / Marked / Invalid / InsidePrivacyArea
            // Fürs Erste 0 / "".
            let confirmedStr = ""  // oder "0"
            let markedStr = ""     // oder "0"
            let invalidStr = "0"
            let insidePrivacyStr = "0"

            // Factor (in deinen Beispielen 58) – wir nehmen 58 als Default.
            let factorStr = "58"

            // Measurements = 1 (wir schreiben pro Zeile eine Messung)
            let measurementsStr = "1"

            // Tms1/Lus1/Rus1: minimal befüllen
            // Für _korrekte_ Rohdaten müsste man die Firmware-Timings kennen.
            // Hier schreiben wir:
            // - Tms1: 0
            // - Lus1: leftCm * 10 (mm) falls Left
            // - Rus1: rightCm * 10 (mm) falls Right
            // Das ist eher ein Platzhalter; Portal kann damit evtl. schon umgehen.
            let tms1 = "0"
            let lus1 = leftCm.map { String($0 * 10) } ?? ""
            let rus1 = rightCm.map { String($0 * 10) } ?? ""

            // Alle Tms2..Rus30 leer
            let emptyTriples = Array(repeating: ["", "", ""], count: 29).flatMap { $0 }

            // Kommentar
            let commentStr = comment ?? ""

            // CSV-Zeile aufbauen
            var fields: [String] = []
            fields.append(contentsOf: [
                dateStr,
                timeStr,
                String(millis),
                commentStr,
                latStr,
                lonStr,
                altStr,
                "",          // Course
                speedStr,
                hdopStr,
                satellitesStr,
                batteryStr,
                leftStr,
                rightStr,
                confirmedStr,
                markedStr,
                invalidStr,
                insidePrivacyStr,
                factorStr,
                measurementsStr,
                tms1,
                lus1,
                rus1
            ])

            fields.append(contentsOf: emptyTriples)

            // Insgesamt sollten es genau so viele Felder sein wie im Header.
            let line = fields.joined(separator: ";") + "\n"

            do {
                try handle.write(contentsOf: Data(line.utf8))
            } catch {
                print("OBSCSVWriter: write error: \(error)")
            }
        }
    }

    /// Session sauber beenden (flush/close)
    func finishSession() {
        queue.sync {
            closeIfNeeded()
        }
    }

    // MARK: - Intern

    private func closeIfNeeded() {
        guard let handle = handle else { return }
        do {
            try handle.synchronize()
        } catch {
            print("OBSCSVWriter: synchronize error: \(error)")
        }
        do {
            try handle.close()
        } catch {
            print("OBSCSVWriter: close error: \(error)")
        }
        self.handle = nil
        print("OBSCSVWriter: finishSession -> \(fileURL?.lastPathComponent ?? "-")")
    }

    private func formatOptional(_ value: Double?, decimals: Int) -> String {
        guard let v = value else { return "" }
        return String(format: "%.\(decimals)f", v)
    }
}
