import Foundation

/// Schreibt COBS-kodierte OBS-Events in eine .bin-Datei,
/// so dass das Portal sie wie unter Android einlesen kann.
final class OBSFileWriter {

    private let queue = DispatchQueue(label: "obs.file.writer")

    private(set) var fileURL: URL?
    private var handle: FileHandle?

    /// Neue Aufnahmesession starten (alte ggf. sauber schließen)
    func startSession() {
        queue.sync {
            // vorherige Session schließen, falls noch offen
            if handle != nil {
                finishSession()
            }

            do {
                let fm = FileManager.default

                // Basis: Documents/OBS
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

                // Dateiname: fahrt_YYYYMMDD_HHmmss.bin
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let stamp = formatter.string(from: Date())

                let file = dir.appendingPathComponent("fahrt_\(stamp).bin")
                fm.createFile(atPath: file.path, contents: nil)

                let fh = try FileHandle(forWritingTo: file)
                self.handle = fh
                self.fileURL = file

                print("OBSFileWriter: startSession -> \(file.path)")
            } catch {
                print("OBSFileWriter: startSession error: \(error)")
                self.handle = nil
                self.fileURL = nil
            }
        }
    }

    /// COBS-kodiertes Frame (inkl. 0x00-Delimiter) schreiben
    func write(_ data: Data) {
        queue.async {
            guard let handle = self.handle else {
                print("OBSFileWriter: write() ohne offene Session")
                return
            }
            do {
                try handle.write(contentsOf: data)
            } catch {
                print("OBSFileWriter: write error: \(error)")
            }
        }
    }

    /// Session sauber beenden (flush/close)
    func finishSession() {
        queue.sync {
            guard let handle = self.handle else { return }
            do {
                try handle.synchronize()
            } catch {
                print("OBSFileWriter: synchronize error: \(error)")
            }
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
