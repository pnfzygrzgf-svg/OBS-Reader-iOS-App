// DataExportView.swift

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Helper: Speicherung der Überholvorgänge & Distanz pro Datei

/// Speichert Auswertungsdaten (Anzahl Überholvorgänge + Distanz) pro Aufnahmedatei
/// in `UserDefaults`, verknüpft über den Dateinamen (lastPathComponent).
struct OvertakeStatsStore {
    private static let countsKey   = "obsOvertakeCounts"
    private static let distanceKey = "obsTrackDistanceMeters"

    /// Speichert Anzahl Überholvorgänge und Distanz (in Metern) für eine Datei.
    ///
    /// - Parameter count: Anzahl der Überholvorgänge (optional, nur wenn > 0 gespeichert)
    /// - Parameter distanceMeters: Distanz in Metern (optional, nur wenn > 0 gespeichert)
    /// - Parameter url: Dateipfad zur .bin-Datei; es wird nur der Dateiname als Schlüssel genutzt.
    static func store(count: Int?, distanceMeters: Double?, for url: URL) {
        let fileKey = url.lastPathComponent

        // Counts
        if let count = count, count > 0 {
            // Bisherige Map aus UserDefaults laden oder leeres Dict anlegen
            var dict = (UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
            dict[fileKey] = count
            UserDefaults.standard.set(dict, forKey: countsKey)
        }

        // Distanz
        if let meters = distanceMeters, meters > 0 {
            var dict = (UserDefaults.standard.dictionary(forKey: distanceKey) as? [String: Double]) ?? [:]
            dict[fileKey] = meters
            UserDefaults.standard.set(dict, forKey: distanceKey)
        }
    }

    /// Lädt gespeicherte Überholvorgänge & Distanz (km) für eine Datei.
    ///
    /// - Parameter url: Dateipfad zur .bin-Datei.
    /// - Returns: Tuple aus (Anzahl Überholvorgänge?, Distanz in km?)
    static func load(for url: URL) -> (count: Int?, distanceKm: Double?) {
        let fileKey = url.lastPathComponent

        let countsDict = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]
        let rawCount = countsDict?[fileKey]

        let distDict = UserDefaults.standard.dictionary(forKey: distanceKey) as? [String: Double]
        let meters = distDict?[fileKey]
        let km = meters.map { $0 / 1000.0 }

        return (rawCount, km)
    }
}

// MARK: - Model

/// Metadaten zu einer OBS-Aufnahmedatei (.bin / .csv)
struct OBSFileInfo: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let sizeDescription: String
    let dateDescription: String
    let modificationDate: Date?

    /// Gespeicherte Anzahl Überholvorgänge für diese Datei (falls vorhanden)
    let overtakeCount: Int?

    /// Gespeicherte Distanz in km (falls vorhanden)
    let distanceKm: Double?
}

/// Wrapper für das iOS-Share Sheet (UIActivityViewController),
/// damit es in SwiftUI via .sheet genutzt werden kann.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - View

/// Listet aufgezeichnete OBS-Dateien aus dem Documents-Ordner
/// und ermöglicht:
/// - Teilen der Datei (Share Sheet)
/// - Hochladen zum OBS-Portal
/// - Löschen einzelner oder aller Dateien
/// - Konfiguration der OBS-Portal-URL und des API-Keys
struct DataExportView: View {

    /// Alle gefundenen OBS-Dateien (bin/csv) im Documents-Ordner
    @State private var files: [OBSFileInfo] = []

    // Sharing
    @State private var isShowingShareSheet = false
    @State private var shareURL: URL?

    // OBS-Portal-Einstellungen (werden dauerhaft gespeichert)
    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""
    @AppStorage("obsApiKey")  private var obsApiKey: String = ""

    // Upload-Status
    @State private var isUploading: Bool = false
    @State private var uploadStatusMessage: String?
    @State private var isShowingUploadResultAlert: Bool = false

    // Bestätigung für Upload (für eine gewählte Datei)
    @State private var isShowingUploadConfirm: Bool = false
    @State private var pendingUploadFile: OBSFileInfo?

    // Bestätigung für Löschen (eine Datei oder alle)
    @State private var isShowingDeleteConfirm: Bool = false
    @State private var pendingDeleteFile: OBSFileInfo?

    var body: some View {
        ZStack {
            // Hintergrund wie auf der Startseite
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    portalConfigCard
                    recordingsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .font(.obsBody)
            }
            .scrollIndicators(.hidden)
            // Pull-to-Refresh lädt die Dateiliste neu
            .refreshable {
                loadFiles()
            }

            // Upload-Overlay unten als dezentes Toast, solange Upload läuft
            if isUploading {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Upload läuft…")
                            .font(.obsBody)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(radius: 4)
                    .padding(.bottom, 16)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("Dateien")
        .toolbar {
            // Toolbar-Button zum Löschen ALLER Dateien
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    if !files.isEmpty {
                        pendingDeleteFile = nil   // nil => alle
                        isShowingDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(files.isEmpty)
                .buttonStyle(.borderless)
                .accessibilityLabel("Alle Dateien löschen")
            }
        }
        .onAppear {
            // Beim Öffnen die aktuelle Dateiliste laden
            loadFiles()
        }
        // Share Sheet
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = shareURL {
                ActivityView(activityItems: [url])
            }
        }
        // Upload-Ergebnis-Alert (mit Statuscode & Antworttext)
        .alert("Upload", isPresented: $isShowingUploadResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uploadStatusMessage ?? "Unbekannter Fehler")
        }
        // Upload-Bestätigung (Einzeldatei)
        .alert("Upload bestätigen", isPresented: $isShowingUploadConfirm) {
            Button("Hochladen", role: .destructive) {
                if let file = pendingUploadFile {
                    upload(file)
                }
                pendingUploadFile = nil
            }
            Button("Abbrechen", role: .cancel) {
                pendingUploadFile = nil
            }
        } message: {
            if let file = pendingUploadFile {
                Text("„\(file.name)“ wirklich zum OBS-Portal hochladen?")
            } else {
                Text("Wirklich zum OBS-Portal hochladen?")
            }
        }
        // Lösch-Bestätigung (eine Datei oder alle)
        .alert("Wirklich löschen?", isPresented: $isShowingDeleteConfirm) {
            Button("Löschen", role: .destructive) {
                if let file = pendingDeleteFile {
                    delete(file)
                } else {
                    deleteAll()
                }
                pendingDeleteFile = nil
            }
            Button("Abbrechen", role: .cancel) {
                pendingDeleteFile = nil
            }
        } message: {
            if let file = pendingDeleteFile {
                Text("Diese Fahrt „\(file.name)“ wird dauerhaft gelöscht.")
            } else {
                Text("Alle Fahrten werden dauerhaft gelöscht.")
            }
        }
    }

    // MARK: - Unterviews

    /// OBS-Portal-Konfiguration als Card:
    /// - Basis-URL
    /// - API-Key
    /// - Statusanzeige, ob Upload möglich ist
    private var portalConfigCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: obsBaseUrl.isEmpty || obsApiKey.isEmpty
                      ? "exclamationmark.triangle.fill"
                      : "checkmark.seal.fill")
                .foregroundStyle(obsBaseUrl.isEmpty || obsApiKey.isEmpty ? .orange : .green)

                Text("OBS-Portal")
                    .font(.obsScreenTitle)

                Spacer()
            }

            Text(obsBaseUrl.isEmpty || obsApiKey.isEmpty
                 ? "OBS-Portal ist noch nicht vollständig eingerichtet."
                 : "OBS-Portal ist bereit zum Hochladen.")
            .font(.obsCaption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Portal-URL")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)

                TextField("https://portal.openbikesensor.org/", text: $obsBaseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .font(.obsBody)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API-Key")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)

                SecureField("API-Key eintragen", text: $obsApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.obsBody)
            }

            if obsBaseUrl.isEmpty || obsApiKey.isEmpty {
                Text("Bitte Portal-URL und API-Key eintragen, um Aufnahmen direkt ins OBS-Portal hochzuladen.")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .obsCardStyle()
    }

    /// Aufnahmen-Abschnitt mit Dateikarten (oder leerem Zustand)
    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aufnahmen")
                .font(.obsScreenTitle)

            if files.isEmpty {
                emptyStateCard
                    .obsCardStyle()
            } else {
                VStack(spacing: 12) {
                    ForEach(files) { file in
                        fileRow(for: file)
                            .obsCardStyle()
                    }
                }
            }
        }
    }

    /// Leerer Zustand, wenn keine Dateien existieren
    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Keine Aufnahmen gefunden")
                .font(.obsSectionTitle)

            Text("Erstelle eine Aufnahme. Danach erscheinen deine .bin-Dateien hier zum Teilen oder Hochladen.")
                .font(.obsFootnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Einzelne Dateikarte mit Name, Größe, Datum und optional Stats
    private func fileRow(for file: OBSFileInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(file.name)
                    .font(.obsSectionTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 12) {
                    Text(file.sizeDescription)
                    Text(file.dateDescription)
                }
                .font(.obsCaption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

                if file.overtakeCount != nil || file.distanceKm != nil {
                    HStack(spacing: 12) {
                        if let count = file.overtakeCount {
                            Text("\(count) Überholvorgänge")
                        }
                        if let km = file.distanceKm {
                            Text("\(String(format: "%.2f", km)) km")
                        }
                    }
                    .font(.obsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            // Bessere VoiceOver-Ausgabe (statt jedes Label einzeln)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(for: file))

            Spacer()

            // Kontextmenü für eine Datei: Teilen / Hochladen / Löschen
            Menu {
                Button {
                    share(file)
                } label: {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }

                Button {
                    pendingUploadFile = file
                    isShowingUploadConfirm = true
                } label: {
                    Label("Hochladen", systemImage: "icloud.and.arrow.up")
                }
                .disabled(isUploading || obsBaseUrl.isEmpty || obsApiKey.isEmpty)

                Button(role: .destructive) {
                    pendingDeleteFile = file
                    isShowingDeleteConfirm = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Primäraktion bei Tap auf die Zeile: Upload-Dialog öffnen
            pendingUploadFile = file
            isShowingUploadConfirm = true
        }
    }

    // MARK: - Dateien laden (rekursiv im ganzen Documents-Ordner)

    /// Sucht im Documents-Ordner (rekursiv) nach .bin/.csv-Dateien
    /// und baut daraus eine sortierte Liste von `OBSFileInfo`.
    private func loadFiles() {
        let fm = FileManager.default

        do {
            let docs = try fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            print("DataExportView: Documents = \(docs.path)")

            // Resource-Keys, die wir für jede Datei auslesen wollen
            let keys: [URLResourceKey] = [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]

            guard let enumerator = fm.enumerator(
                at: docs,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                print("DataExportView: kein Enumerator für Documents")
                files = []
                return
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            var found: [OBSFileInfo] = []

            // Alle Dateien durchlaufen (rekursiv)
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                // Nur OBS-relevante Dateien
                guard ext == "bin" || ext == "csv" else { continue }

                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isRegularFile == true else { continue }

                    let size = values.fileSize.map { formatBytes($0) } ?? "–"
                    let date = values.contentModificationDate
                    let dateDesc = date.map { formatter.string(from: $0) } ?? "–"

                    // Überhol-Statistik aus UserDefaults laden
                    let stats = OvertakeStatsStore.load(for: url)

                    let info = OBSFileInfo(
                        url: url,
                        name: url.lastPathComponent,
                        sizeDescription: size,
                        dateDescription: dateDesc,
                        modificationDate: date,
                        overtakeCount: stats.count,
                        distanceKm: stats.distanceKm
                    )
                    found.append(info)
                } catch {
                    print("DataExportView: Attribute-Fehler für \(url.path): \(error)")
                }
            }

            print("DataExportView: gefunden \(found.count) .bin/.csv Dateien")

            // Neueste zuerst nach Änderungsdatum, Fallback auf alphabetische Reihenfolge
            files = found.sorted { lhs, rhs in
                let lDate = lhs.modificationDate ?? .distantPast
                let rDate = rhs.modificationDate ?? .distantPast
                if lDate == rDate {
                    return lhs.name < rhs.name
                } else {
                    return lDate > rDate
                }
            }

        } catch {
            print("DataExportView: loadFiles error: \(error)")
            files = []
        }
    }

    // MARK: - Teilen

    /// Teilt eine KOPIE im tmp-Ordner (Original bleibt im Documents-Ordner).
    /// So wird verhindert, dass der Share-Empfänger direkt auf das „echte“ File zugreift.
    private func share(_ file: OBSFileInfo) {
        let fm = FileManager.default

        do {
            let tempDir = fm.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(file.name)

            if fm.fileExists(atPath: tempURL.path) {
                try fm.removeItem(at: tempURL)
            }

            try fm.copyItem(at: file.url, to: tempURL)

            print("DataExportView: teile temporäre Datei: \(tempURL.path)")

            shareURL = tempURL
            isShowingShareSheet = true
        } catch {
            print("DataExportView: Fehler beim Vorbereiten der Datei zum Teilen: \(error)")
        }
    }

    // MARK: - Hochladen

    /// Startet Upload einer Datei zum OBS-Portal.
    /// - Prüft zunächst, ob Basis-URL und API-Key vorhanden sind.
    /// - Zeigt nach Abschluss einen Alert mit Status und Antworttext.
    private func upload(_ file: OBSFileInfo) {
        guard !obsBaseUrl.isEmpty, !obsApiKey.isEmpty else {
            uploadStatusMessage = "Bitte Basis-URL und API-Key ausfüllen."
            isShowingUploadResultAlert = true
            return
        }

        isUploading = true

        Task {
            do {
                let result = try await OBSUploader.shared.uploadTrack(
                    fileURL: file.url,
                    baseUrl: obsBaseUrl,
                    apiKey: obsApiKey
                )

                if result.isSuccessful {
                    uploadStatusMessage =
                        "Datei „\(file.name)“ wurde erfolgreich hochgeladen.\n" +
                        "Status: \(result.statusCode)\n\nAntwort:\n\(result.responseBody)"
                } else {
                    uploadStatusMessage =
                        "Upload der Datei „\(file.name)“ fehlgeschlagen.\n" +
                        "Status: \(result.statusCode)\n\nAntwort:\n\(result.responseBody)"
                }
            } catch {
                uploadStatusMessage = "Upload-Fehler für „\(file.name)“: \(error.localizedDescription)"
            }

            isUploading = false
            isShowingUploadResultAlert = true
        }
    }

    // MARK: - Löschen

    /// Löscht eine einzelne Datei vom Dateisystem und lädt die Liste neu.
    private func delete(_ file: OBSFileInfo) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: file.url)
            loadFiles()
        } catch {
            print("DataExportView: Fehler beim Löschen von \(file.url): \(error)")
        }
    }

    /// Löscht alle aktuell gelisteten Dateien.
    private func deleteAll() {
        let fm = FileManager.default
        for file in files {
            do {
                try fm.removeItem(at: file.url)
            } catch {
                print("DataExportView: Fehler beim Löschen von \(file.url): \(error)")
            }
        }
        loadFiles()
    }

    // MARK: - Helfer

    /// Formatiert eine Byte-Anzahl in ein lesbares Label (B, KB, MB).
    private func formatBytes(_ bytes: Int) -> String {
        let b = Double(bytes)
        if b < 1024 {
            return "\(bytes) B"
        }
        let kb = b / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.2f MB", mb)
    }

    /// Zusammengefasster VoiceOver-Text für eine Datei (Name, Größe, Datum, Stats).
    private func accessibilityText(for file: OBSFileInfo) -> String {
        var parts: [String] = []
        parts.append(file.name)
        parts.append("Größe \(file.sizeDescription)")
        parts.append("geändert am \(file.dateDescription)")

        if let count = file.overtakeCount {
            parts.append("\(count) Überholvorgänge")
        }

        if let km = file.distanceKm {
            parts.append("\(String(format: "%.2f", km)) Kilometer")
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DataExportView()
    }
}
