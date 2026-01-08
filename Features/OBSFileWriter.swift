// OBSFileWriter.swift

import Foundation

/// Schreibt COBS-kodierte OBS-Events in eine .bin-Datei,
/// so dass das Portal sieeinlesen kann.
///
/// Lebenszyklus:
/// - `startSession()` öffnet eine neue Datei unter Documents/OBS/...
/// - `write(_:)` hängt COBS-kodierte Frames (inkl. 0x00-Delimiter) an
/// - `finishSession()` flusht und schließt die Datei
final class OBSFileWriter {

    /// Serielle Queue, um Dateioperationen threadsicher auszuführen.
    /// Alle Zugriffe auf `handle` und `fileURL` laufen über diese Queue.
    private let queue = DispatchQueue(label: "obs.file.writer")

    /// URL der aktuell geöffneten Datei (falls eine Session läuft)
    private(set) var fileURL: URL?
    /// Offene FileHandle-Instanz zum Schreiben in die Datei
    private var handle: FileHandle?

    /// Neue Aufnahmesession starten (alte ggf. sauber schließen).
    ///
    /// Öffnet eine neue .bin-Datei im Verzeichnis:
    ///   Documents/OBS/fahrt_YYYYMMDD_HHmmss.bin
    ///
    /// Thread-Sicherheit:
    /// - Läuft synchron auf `queue`, damit nicht parallel geschrieben wird.
    func startSession() {
        queue.sync {
            // vorherige Session schließen, falls noch offen
            if handle != nil {
                finishSession()
            }

            do {
                let fm = FileManager.default

                // Basis: Documents/OBS
                // Documents-Verzeichnis des Users holen (z. B. für iTunes/Files-App sichtbar)
                let docs = try fm.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                // Unterordner "OBS" anlegen (falls noch nicht vorhanden)
                let dir = docs.appendingPathComponent("OBS", isDirectory: true)

                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }

                // Dateiname: fahrt_YYYYMMDD_HHmmss.bin
                // Stempelformat so wählen, dass es sich gut sortieren lässt.
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                formatter.locale = Locale(identifier: "en_US_POSIX") // stabil, unabhängig von Gerätesprache
                let stamp = formatter.string(from: Date())

                let file = dir.appendingPathComponent("fahrt_\(stamp).bin")

                // Datei anlegen (leer)
                fm.createFile(atPath: file.path, contents: nil)

                // FileHandle zum Schreiben öffnen
                let fh = try FileHandle(forWritingTo: file)
                self.handle = fh
                self.fileURL = file

                print("OBSFileWriter: startSession -> \(file.path)")
            } catch {
                // Bei jedem Fehler: Handle und URL zurücksetzen, damit nichts „halb-offen“ bleibt.
                print("OBSFileWriter: startSession error: \(error)")
                self.handle = nil
                self.fileURL = nil
            }
        }
    }

    /// COBS-kodiertes Frame (inkl. 0x00-Delimiter) schreiben.
    ///
    /// Erwartung:
    /// - `data` enthält **bereits** den COBS-codierten Block **plus**
    ///   das abschließende 0x00 als Frame-Delimiter.
    ///
    /// Thread-Sicherheit:
    /// - Schreibt asynchron auf der `queue`, um UI-Thread nicht zu blockieren.
    func write(_ data: Data) {
        queue.async {
            guard let handle = self.handle else {
                // write() wurde ohne vorherige startSession() bzw. nach finishSession() aufgerufen
                print("OBSFileWriter: write() ohne offene Session")
                return
            }
            do {
                // Daten direkt an die Datei anhängen
                try handle.write(contentsOf: data)
            } catch {
                print("OBSFileWriter: write error: \(error)")
            }
        }
    }

    /// Session sauber beenden (flush/close).
    ///
    /// - Synchronisiert gepufferte Daten auf den Datenträger (`synchronize()`),
    /// - schließt den FileHandle (`close()`),
    /// - setzt `handle` wieder auf `nil`.
    ///
    /// Kann gefahrlos mehrfach aufgerufen werden: wenn `handle == nil`, passiert nichts.
    func finishSession() {
        queue.sync {
            guard let handle = self.handle else { return }

            // Noch im Puffer befindliche Daten auf die Platte schreiben
            do {
                try handle.synchronize()
            } catch {
                print("OBSFileWriter: synchronize error: \(error)")
            }

            // Datei-Handle schließen
            do {
                try handle.close()
            } catch {
                print("OBSFileWriter: close error: \(error)")
            }

            self.handle = nil
            print("OBSFileWriter: finishSession -> \(fileURL?.lastPathComponent ?? "-")")
        }
    }
}
