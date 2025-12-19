import SwiftUI
import UniformTypeIdentifiers

// =====================================================
// MARK: - Helper: Speicherung der Überholvorgänge & Distanz pro Datei
// =====================================================

/// Speichert Auswertungsdaten (Anzahl Überholvorgänge + Distanz) pro Aufnahmedatei
/// in `UserDefaults`, verknüpft über den Dateinamen (lastPathComponent).
///
/// Warum so?
/// - Die Auswertungsdaten sind “Meta-Infos” zur Datei (nicht Teil der CSV/BIN selbst).
/// - Der Dateiname (lastPathComponent) ist ein stabiler Schlüssel für die Datei.
/// - UserDefaults eignet sich für kleine Key-Value Daten (nicht für große Dateien).
struct OvertakeStatsStore {
    /// Key für Dictionary: [Dateiname: Überholcount]
    private static let countsKey   = "obsOvertakeCounts"

    /// Key für Dictionary: [Dateiname: Distanz in Metern]
    private static let distanceKey = "obsTrackDistanceMeters"

    /// Speichert (optional) Count/Distanz für eine bestimmte Datei.
    /// - Nur Werte > 0 werden geschrieben (nil/0 wird ignoriert).
    static func store(count: Int?, distanceMeters: Double?, for url: URL) {
        // Wir verwenden nur den Dateinamen als Schlüssel (ohne Pfad),
        // damit es unabhängig davon bleibt, wo die Datei im Documents liegt.
        let fileKey = url.lastPathComponent

        // --- Count speichern ---
        if let count = count, count > 0 {
            // Dictionary aus UserDefaults lesen oder neu anlegen
            var dict = (UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
            dict[fileKey] = count
            UserDefaults.standard.set(dict, forKey: countsKey)
        }

        // --- Distanz speichern (in Metern) ---
        if let meters = distanceMeters, meters > 0 {
            var dict = (UserDefaults.standard.dictionary(forKey: distanceKey) as? [String: Double]) ?? [:]
            dict[fileKey] = meters
            UserDefaults.standard.set(dict, forKey: distanceKey)
        }
    }

    /// Lädt die gespeicherten Werte für eine Datei.
    /// - distance wird intern in Metern gespeichert, für die UI in km umgerechnet.
    static func load(for url: URL) -> (count: Int?, distanceKm: Double?) {
        let fileKey = url.lastPathComponent

        // Count aus Dictionary laden
        let countsDict = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]
        let rawCount = countsDict?[fileKey]

        // Distanz (Meter) aus Dictionary laden und in km umrechnen
        let distDict = UserDefaults.standard.dictionary(forKey: distanceKey) as? [String: Double]
        let meters = distDict?[fileKey]
        let km = meters.map { $0 / 1000.0 }

        return (rawCount, km)
    }
}

// =====================================================
// MARK: - Model
// =====================================================

/// Metadaten zu einer OBS-Aufnahmedatei (.bin / .csv), so wie sie in der Liste angezeigt wird.
struct OBSFileInfo: Identifiable {
    /// Stable ID für SwiftUI Listen (hier: random UUID pro Reload).
    /// Hinweis: Wenn du wirklich stabile IDs über App-Starts brauchst, könntest du `url` als ID verwenden.
    let id = UUID()

    /// Datei-URL im Documents-Ordner (oder Unterordner).
    let url: URL

    /// Anzeigename (typisch: Dateiname).
    let name: String

    /// Formatierte Größe (z.B. "12.3 KB").
    let sizeDescription: String

    /// Formatierte Änderungszeit (z.B. "14.12.25, 12:34").
    let dateDescription: String

    /// Unformatierte Änderungszeit (für Sortierung).
    let modificationDate: Date?

    /// Auswertung: Anzahl Überholvorgänge (optional).
    let overtakeCount: Int?

    /// Auswertung: Distanz in km (optional).
    let distanceKm: Double?
}

/// Wrapper für das iOS-Share Sheet (UIActivityViewController),
/// damit es in SwiftUI via `.sheet` genutzt werden kann.
struct ActivityView: UIViewControllerRepresentable {
    /// Items, die geteilt werden sollen (hier typischerweise: eine Datei-URL).
    let activityItems: [Any]

    /// Erstellt den UIKit-Controller einmalig für das Share Sheet.
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    /// Wird von SwiftUI aufgerufen, wenn sich State ändert.
    /// Hier kein Update nötig, weil das Share Sheet nicht dynamisch "weitergerendert" wird.
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Kein Live-Update nötig (Share Sheet ist “fire and forget”).
    }
}

// =====================================================
// MARK: - View
// =====================================================

/// Listet aufgezeichnete OBS-Dateien aus dem Documents-Ordner
/// und ermöglicht:
/// - Teilen der Datei (Share Sheet)
/// - Hochladen zum OBS-Portal (via OBSUploader)
/// - Löschen einzelner oder aller Dateien
struct DataExportView: View {

    // -------------------------------------------------
    // MARK: State
    // -------------------------------------------------

    /// Geladene Dateien (wird bei onAppear/refreshable aktualisiert).
    @State private var files: [OBSFileInfo] = []

    /// Share Sheet State: zeigt UIActivityViewController als Sheet.
    @State private var isShowingShareSheet = false
    @State private var shareURL: URL?

    /// Portal-Konfiguration (persistiert per AppStorage).
    /// Kommt üblicherweise aus einem Settings-Screen.
    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""
    @AppStorage("obsApiKey")  private var obsApiKey: String = ""

    /// Upload-Status / UI Feedback.
    @State private var isUploading: Bool = false
    @State private var uploadStatusMessage: String?
    @State private var isShowingUploadResultAlert: Bool = false

    /// Upload-Confirmation für einzelne Datei.
    @State private var isShowingUploadConfirm: Bool = false
    @State private var pendingUploadFile: OBSFileInfo?

    /// Delete-Confirmation (eine Datei oder alle).
    @State private var isShowingDeleteConfirm: Bool = false
    @State private var pendingDeleteFile: OBSFileInfo?

    /// Portal ist nur dann “ready”, wenn URL und API Key gesetzt sind.
    private var portalConfigured: Bool {
        !obsBaseUrl.isEmpty && !obsApiKey.isEmpty
    }

    // -------------------------------------------------
    // MARK: Body
    // -------------------------------------------------

    var body: some View {
        ZStack {
            // Hintergrund im iOS “grouped” Look.
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Hinweis-Karte, wenn Portal noch nicht konfiguriert ist.
                    if !portalConfigured {
                        portalHintCard
                            .obsCardStyle()
                    }

                    // Sektion mit Liste der Dateien oder Empty State.
                    recordingsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .font(.obsBody)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                // Pull-to-refresh lädt die Dateien erneut vom Dateisystem.
                loadFiles()
            }

            // Upload-Overlay: kleines HUD am unteren Rand (solange Upload läuft).
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
        .navigationTitle("Fahrten auf dem Gerät")
        .toolbar {
            // Toolbar: “Alle löschen”
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    // Confirmation nur anzeigen, wenn überhaupt Dateien existieren.
                    if !files.isEmpty {
                        pendingDeleteFile = nil   // nil => bedeutet “alle”
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
            // Beim ersten Anzeigen laden wir die Dateien.
            loadFiles()
        }
        .sheet(isPresented: $isShowingShareSheet) {
            // Share Sheet wird präsentiert, wenn `shareURL` gesetzt ist.
            if let url = shareURL {
                ActivityView(activityItems: [url])
            }
        }
        // Upload Result Alert (Erfolg/Fehlertext).
        .alert("Upload", isPresented: $isShowingUploadResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uploadStatusMessage ?? "Unbekannter Fehler")
        }
        // Upload Confirmation Alert (pro Datei).
        .alert("Upload bestätigen", isPresented: $isShowingUploadConfirm) {
            Button("Hochladen", role: .destructive) {
                // Nur wenn eine Datei pending ist, starten wir den Upload.
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
        // Delete Confirmation Alert (einzeln oder alle).
        .alert("Wirklich löschen?", isPresented: $isShowingDeleteConfirm) {
            Button("Löschen", role: .destructive) {
                // pendingDeleteFile == nil bedeutet “alle”.
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

    // =====================================================
    // MARK: - Unterviews
    // =====================================================

    /// Hinweis, dass die Portal-Konfiguration in einem anderen Screen passiert.
    private var portalHintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Portal noch nicht eingerichtet")
                    .font(.obsSectionTitle)
            }

            Text("Um Fahrten direkt ins OBS-Portal hochzuladen, bitte im Bereich Aufzeichnungen, Portal-Einstellungen die Portal-URL und den API-Key eintragen.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Sektion mit Dateiliste oder Empty State.
    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dateien")
                .font(.obsScreenTitle)

            if files.isEmpty {
                // Kein Inhalt: „leerer Zustand“
                emptyStateCard
                    .obsCardStyle()
            } else {
                // Dateien vorhanden: jede Datei als eigene Karte/Zeile
                VStack(spacing: 12) {
                    ForEach(files) { file in
                        fileRow(for: file)
                            .obsCardStyle()
                    }
                }
            }
        }
    }

    /// UI für “keine Dateien vorhanden”.
    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Keine Fahrtauszeichnung gefunden")
                .font(.obsSectionTitle)

            Text("Erstelle eine Fahrtauszeichnung. Danach erscheinen deine .bin-Dateien hier zum Teilen oder Hochladen.")
                .font(.obsFootnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Zeile/Karte für eine einzelne Datei inkl. Menü (Teilen/Hochladen/Löschen).
    private func fileRow(for file: OBSFileInfo) -> some View {
        HStack(spacing: 12) {
            // Linke Seite: Dateiinformationen
            VStack(alignment: .leading, spacing: 6) {
                Text(file.name)
                    .font(.obsSectionTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Größe + Datum
                HStack(spacing: 12) {
                    Text(file.sizeDescription)
                    Text(file.dateDescription)
                }
                .font(.obsCaption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

                // Optional: Stats (Überholcount/Distanz)
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
            // Accessibility: eigener, gut vorlesbarer String (statt viele Einzel-Labels)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(for: file))

            Spacer()

            // Rechte Seite: Context-Menü (ellipsis)
            Menu {
                // Teilen: kopiert Datei in temp und öffnet Share Sheet
                Button {
                    share(file)
                } label: {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }

                // Upload: nur wenn Portal konfiguriert & nicht gerade upload
                Button {
                    pendingUploadFile = file
                    isShowingUploadConfirm = true
                } label: {
                    Label("Hochladen", systemImage: "icloud.and.arrow.up")
                }
                .disabled(isUploading || !portalConfigured)

                // Löschen (mit Bestätigung)
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
        // Ganze Karte tappable machen (nicht nur das Menü-Icon)
        .contentShape(Rectangle())
        .onTapGesture {
            // Shortcut: Tap auf Karte => Upload bestätigen (wie ein „schneller Upload“)
            pendingUploadFile = file
            isShowingUploadConfirm = true
        }
    }

    // =====================================================
    // MARK: - Dateien laden / teilen / upload / löschen
    // =====================================================

    /// Liest .bin und .csv Dateien aus dem Documents-Ordner (inkl. Unterordner)
    /// und baut daraus `OBSFileInfo` Objekte für die UI.
    private func loadFiles() {
        let fm = FileManager.default

        do {
            // Documents directory (Sandbox der App)
            let docs = try fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            // Attribute, die wir beim Enumerieren direkt mit abrufen
            let keys: [URLResourceKey] = [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]

            // Rekursiver Enumerator über Documents
            // options: .skipsHiddenFiles => ignoriert z.B. .DS_Store
            guard let enumerator = fm.enumerator(
                at: docs,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                files = []
                return
            }

            // Formatierung für Anzeige (lokalisiert)
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            var found: [OBSFileInfo] = []

            for case let url as URL in enumerator {
                // Nur OBS-Formate anzeigen
                let ext = url.pathExtension.lowercased()
                guard ext == "bin" || ext == "csv" else { continue }

                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    // Nur echte Dateien, keine Ordner/Symlinks
                    guard values.isRegularFile == true else { continue }

                    // Größe & Änderungsdatum lesen
                    let size = values.fileSize.map { formatBytes($0) } ?? "–"
                    let date = values.contentModificationDate
                    let dateDesc = date.map { formatter.string(from: $0) } ?? "–"

                    // Auswertung (Count/Distanz) aus UserDefaults holen
                    let stats = OvertakeStatsStore.load(for: url)

                    // UI-Model bauen
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
                    // Einzelne Datei ist kaputt/unlesbar -> weiter machen, nicht komplett abbrechen
                    print("DataExportView: Attribute-Fehler für \(url.path): \(error)")
                }
            }

            // Sortieren: neueste zuerst, bei Gleichheit alphabetisch
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
            // z.B. Documents directory nicht lesbar (selten)
            print("DataExportView: loadFiles error: \(error)")
            files = []
        }
    }

    /// Bereitet “Teilen” vor:
    /// - kopiert Datei in temporäres Verzeichnis (häufig kompatibler für Share Sheet)
    /// - zeigt Share Sheet mit dieser Temp-URL
    private func share(_ file: OBSFileInfo) {
        let fm = FileManager.default

        do {
            let tempDir = fm.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(file.name)

            // Bestehende Temp-Datei entfernen, falls vorhanden
            if fm.fileExists(atPath: tempURL.path) {
                try fm.removeItem(at: tempURL)
            }

            // Original nach temp kopieren
            try fm.copyItem(at: file.url, to: tempURL)

            // Share Sheet triggern
            shareURL = tempURL
            isShowingShareSheet = true
        } catch {
            print("DataExportView: Fehler beim Vorbereiten der Datei zum Teilen: \(error)")
        }
    }

    /// Startet Upload einer Datei zum OBS-Portal (async/await).
    /// - Zeigt währenddessen “Upload läuft…” Overlay.
    /// - Ergebnis wird als Alert angezeigt.
    private func upload(_ file: OBSFileInfo) {
        // Schutz: ohne Konfiguration kein Upload möglich
        guard portalConfigured else {
            uploadStatusMessage = "Bitte im Portal-Bereich Portal-URL und API-Key eintragen."
            isShowingUploadResultAlert = true
            return
        }

        // UI: Upload HUD anzeigen
        isUploading = true

        // Task: async Upload ohne UI zu blockieren
        Task {
            do {
                let result = try await OBSUploader.shared.uploadTrack(
                    fileURL: file.url,
                    baseUrl: obsBaseUrl,
                    apiKey: obsApiKey
                )

                // Ergebnistext für Alert aufbereiten
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

            // UI zurücksetzen und Alert zeigen
            isUploading = false
            isShowingUploadResultAlert = true
        }
    }

    /// Löscht eine einzelne Datei und lädt Liste neu.
    private func delete(_ file: OBSFileInfo) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: file.url)
            loadFiles()
        } catch {
            print("DataExportView: Fehler beim Löschen von \(file.url): \(error)")
        }
    }

    /// Löscht alle gefundenen Dateien und lädt Liste neu.
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

    /// Formatiert Bytes in B / KB / MB (für UI Anzeige).
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

    /// Baut einen gut lesbaren VoiceOver-Text aus allen verfügbaren Infos.
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

// =====================================================
// MARK: - Preview
// =====================================================

#Preview {
    NavigationStack {
        DataExportView()
    }
}
