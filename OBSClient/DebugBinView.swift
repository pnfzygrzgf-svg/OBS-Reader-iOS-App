import SwiftUI
import SwiftProtobuf

/// Kleine Debug-Ansicht zum Prüfen der letzten BIN-Datei in Documents/OBS.
struct DebugBinView: View {

    @State private var statusText: String = "Noch keine Prüfung durchgeführt."
    @State private var fileName: String = "–"
    @State private var fileSize: Int = 0

    @State private var nonEmptyChunks: Int = 0
    @State private var okCount: Int = 0
    @State private var errorCount: Int = 0

    // Zusätzliche Statistiken
    @State private var distanceCount: Int = 0
    @State private var geoCount: Int = 0
    @State private var userInputCount: Int = 0
    @State private var otherCount: Int = 0
    @State private var leftDistanceCount: Int = 0
    @State private var rightDistanceCount: Int = 0

    @State private var isRunning: Bool = false
    @State private var progress: Double = 0.0   // 0.0–1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Group {
                Text("BIN-Debug")
                    .font(.title2.bold())

                Text(statusText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Datei: \(fileName)")
                    Text("Größe: \(fileSize) Bytes")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Chunk-Statistik")
                    .font(.headline)

                HStack {
                    Text("Nicht leere Chunks:")
                    Spacer()
                    Text("\(nonEmptyChunks)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("OK (Event geparst):")
                    Spacer()
                    Text("\(okCount)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Fehler:")
                    Spacer()
                    Text("\(errorCount)")
                        .font(.system(.body, design: .monospaced))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Event-Statistik")
                    .font(.headline)

                HStack {
                    Text("DistanceMeasurement gesamt:")
                    Spacer()
                    Text("\(distanceCount)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("↳ Links (sourceID=1):")
                    Spacer()
                    Text("\(leftDistanceCount)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("↳ Rechts (sourceID≠1):")
                    Spacer()
                    Text("\(rightDistanceCount)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Geolocation-Events:")
                    Spacer()
                    Text("\(geoCount)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("UserInput-Events (Button):")
                    Spacer()
                    Text("\(userInputCount)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Sonstige Events:")
                    Spacer()
                    Text("\(otherCount)")
                        .font(.system(.body, design: .monospaced))
                }
            }

            if isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prüfung läuft …")
                        .font(.subheadline)
                    ProgressView(value: progress)
                }
            }

            Spacer()

            Button(action: {
                runDebugValidation()
            }) {
                HStack {
                    Image(systemName: "ladybug.fill")
                    Text("Letzte BIN prüfen")
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.15))
                .clipShape(Capsule())
            }
            .disabled(isRunning)

        }
        .padding()
        .navigationTitle("BIN-Debug")
    }

    // MARK: - Debug-Logik

    private func runDebugValidation() {
        isRunning = true
        progress = 0.0
        statusText = "Suche letzte BIN-Datei in Documents/OBS …"
        fileName = "–"
        fileSize = 0

        nonEmptyChunks = 0
        okCount = 0
        errorCount = 0

        distanceCount = 0
        geoCount = 0
        userInputCount = 0
        otherCount = 0
        leftDistanceCount = 0
        rightDistanceCount = 0

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fm = FileManager.default
                let docs = try fm.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )
                let dir = docs.appendingPathComponent("OBS", isDirectory: true)

                let allFiles = try fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ).filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ext == "bin" || ext == "obsr"
                }

                if allFiles.isEmpty {
                    DispatchQueue.main.async {
                        self.statusText = "Keine .bin/.obsr-Datei in Documents/OBS gefunden."
                        self.isRunning = false
                    }
                    return
                }

                // Neueste Datei nach Änderungsdatum
                let sorted = try allFiles.sorted { a, b in
                    let va = try a.resourceValues(forKeys: [.contentModificationDateKey])
                    let vb = try b.resourceValues(forKeys: [.contentModificationDateKey])
                    return (va.contentModificationDate ?? .distantPast)
                        < (vb.contentModificationDate ?? .distantPast)
                }

                let fileURL = sorted.last!
                let data = try Data(contentsOf: fileURL)
                let size = data.count

                DispatchQueue.main.async {
                    self.fileName = fileURL.lastPathComponent
                    self.fileSize = size
                    self.statusText = "Prüfe \(fileURL.lastPathComponent) (\(size) Bytes)…"
                }

                // In Chunks an 0x00 aufteilen
                let bytes = [UInt8](data)
                var chunks: [Data] = []
                var start = 0
                for i in 0..<bytes.count {
                    if bytes[i] == 0x00 {
                        let len = i - start
                        let chunk = len > 0 ? Data(bytes[start..<i]) : Data()
                        chunks.append(chunk)
                        start = i + 1
                    }
                }
                if start < bytes.count {
                    let chunk = Data(bytes[start..<bytes.count])
                    chunks.append(chunk)
                }

                let totalChunks = max(chunks.count, 1)
                print("BIN_DEBUG: Datei \(fileURL.lastPathComponent), size=\(size), chunks=\(chunks.count)")

                var localNonEmpty = 0
                var localOk = 0
                var localErrors = 0

                var localDistance = 0
                var localGeo = 0
                var localUserInput = 0
                var localOther = 0
                var localLeft = 0
                var localRight = 0

                for (idx, chunk) in chunks.enumerated() {
                    if chunk.isEmpty {
                        print("BIN_DEBUG: #\(idx) leerer Chunk")
                    } else {
                        localNonEmpty += 1
                        do {
                            guard let decoded = cobsDecode(chunk) else {
                                throw NSError(
                                    domain: "COBS",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "COBS decode lieferte nil"]
                                )
                            }
                            let event = try Openbikesensor_Event(serializedData: decoded)

                            // Event-Typ auswerten
                            switch event.content {
                            case .distanceMeasurement(let dm)?:
                                localDistance += 1
                                if dm.sourceID == 1 {
                                    localLeft += 1
                                } else {
                                    localRight += 1
                                }
                            case .geolocation?:
                                localGeo += 1
                            case .userInput?:
                                localUserInput += 1
                            case .textMessage?, .metadata?, .batteryStatus?:
                                localOther += 1
                            case nil:
                                localOther += 1
                            }

                            print(
                                "BIN_DEBUG: #\(idx) OK (chunkLen=\(chunk.count), decodedLen=\(decoded.count))"
                            )
                            localOk += 1
                        } catch {
                            print(
                                "BIN_DEBUG: #\(idx) FEHLER beim Parsen (chunkLen=\(chunk.count)): \(error)"
                            )
                            localErrors += 1
                        }
                    }

                    let prog = Double(idx + 1) / Double(totalChunks)
                    DispatchQueue.main.async {
                        self.progress = prog
                    }
                }

                DispatchQueue.main.async {
                    self.nonEmptyChunks = localNonEmpty
                    self.okCount = localOk
                    self.errorCount = localErrors
                    self.distanceCount = localDistance
                    self.geoCount = localGeo
                    self.userInputCount = localUserInput
                    self.otherCount = localOther
                    self.leftDistanceCount = localLeft
                    self.rightDistanceCount = localRight

                    self.statusText = """
                    Fertig: Größe=\(size) B, nicht leere Chunks=\(localNonEmpty), OK=\(localOk), Fehler=\(localErrors)
                    Distance=\(localDistance), Geolocation=\(localGeo), UserInput=\(localUserInput), Other=\(localOther)
                    (Details im Xcode-Log unter \"BIN_DEBUG\")
                    """
                    self.progress = 1.0
                    self.isRunning = false
                }

            } catch {
                DispatchQueue.main.async {
                    self.statusText = "Fehler beim Prüfen: \(error.localizedDescription)"
                    self.isRunning = false
                    self.progress = 0.0
                }
            }
        }
    }

    // MARK: - COBS Decode (lokal)

    /// Dekodiert einen COBS-kodierten Block (ohne oder mit optionalem 0x00 am Ende).
    private func cobsDecode(_ data: Data) -> Data? {
        if data.isEmpty { return data }

        var out = Data()
        out.reserveCapacity(data.count)

        var index = 0

        // Falls das letzte Byte 0x00 ist, ignorieren.
        let effectiveLength: Int = {
            if data.last == 0x00 {
                return max(0, data.count - 1)
            } else {
                return data.count
            }
        }()

        let bytes = [UInt8](data)

        while index < effectiveLength {
            let code = Int(bytes[index])
            if code == 0 {
                // Ungültiger COBS-Frame
                return nil
            }
            index += 1

            let end = index + code - 1
            while index < end && index < effectiveLength {
                out.append(bytes[index])
                index += 1
            }

            // Wenn der Code < 0xFF und wir noch nicht am Ende sind,
            // fügen wir ein implizites 0x00 ein.
            if code < 0xFF && index < effectiveLength {
                out.append(0)
            }
        }

        return out
    }
}
