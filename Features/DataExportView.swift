// DataExportView.swift

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
        let fileKey = url.lastPathComponent

        // --- Count speichern ---
        if let count = count, count > 0 {
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

        let countsDict = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]
        let rawCount = countsDict?[fileKey]

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
    let id = UUID()
    let url: URL
    let name: String
    let sizeDescription: String
    let dateDescription: String
    let modificationDate: Date?
    let overtakeCount: Int?
    let distanceKm: Double?
}

/// Wrapper für das iOS-Share Sheet (UIActivityViewController),
/// damit es in SwiftUI via `.sheet` genutzt werden kann.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

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
///
/// OPTIK-UPDATE:
/// - ruhige iOS-Inset-Grouped Cards (über obsCardStyleV2())
/// - klarer Empty State
/// - Row-Optik: Dateiname + Meta + optional Stats
///
/// TECH-FIX:
/// - nutzt V2-Komponenten, um Kollisionen/“ambiguous“ Fehler zu vermeiden:
///   - OBSSectionHeaderV2 statt OBSSectionHeader
///   - obsCardStyleV2() statt obsCardStyle()
/// - umgeht `.toolbar` Ambiguity über `.navigationBarItems`
struct DataExportView: View {

    // -------------------------------------------------
    // MARK: State
    // -------------------------------------------------

    @State private var files: [OBSFileInfo] = []

    @State private var isShowingShareSheet = false
    @State private var shareURL: URL?

    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""
    @AppStorage("obsApiKey")  private var obsApiKey: String = ""

    @State private var isUploading: Bool = false
    @State private var uploadStatusMessage: String?
    @State private var isShowingUploadResultAlert: Bool = false
    @State private var uploadTask: Task<Void, Never>?

    @State private var isShowingUploadConfirm: Bool = false
    @State private var pendingUploadFile: OBSFileInfo?

    @State private var isShowingDeleteConfirm: Bool = false
    @State private var pendingDeleteFile: OBSFileInfo?

    private var portalConfigured: Bool {
        !obsBaseUrl.isEmpty && !obsApiKey.isEmpty
    }

    // -------------------------------------------------
    // MARK: Body
    // -------------------------------------------------

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if !portalConfigured {
                        portalHintCard
                            .obsCardStyleV2()
                    }

                    recordingsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .font(.obsBody)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                loadFiles()
            }

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
        .navigationBarTitleDisplayMode(.inline)

        // ✅ TECH-FIX: statt .toolbar (bei dir “ambiguous”) nutzen wir navigationBarItems.
        .navigationBarItems(trailing: deleteAllButton)

        .onAppear {
            loadFiles()
        }
        .onDisappear {
            // Upload-Task abbrechen wenn View verschwindet
            uploadTask?.cancel()
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = shareURL {
                ActivityView(activityItems: [url])
            }
        }
        .alert("Upload", isPresented: $isShowingUploadResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uploadStatusMessage ?? "Unbekannter Fehler")
        }
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

    /// NavigationBar Button: “Alle löschen”
    private var deleteAllButton: some View {
        Button(action: {
            if !files.isEmpty {
                pendingDeleteFile = nil
                isShowingDeleteConfirm = true
            }
        }) {
            Image(systemName: "trash")
        }
        .disabled(files.isEmpty)
        .accessibilityLabel("Alle Dateien löschen")
    }

    // =====================================================
    // MARK: - Unterviews
    // =====================================================

    private var portalHintCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Portal noch nicht eingerichtet")
                    .font(.obsSectionTitle)
            }

            Text("Um Fahrten direkt ins OBS-Portal hochzuladen, bitte im Bereich Aufzeichnungen → Portal-Einstellungen die Portal-URL und den API-Key eintragen.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OBSSectionHeaderV2("Dateien", subtitle: "Teilen, hochladen oder löschen.")

            if files.isEmpty {
                emptyStateCard
                    .obsCardStyleV2()
            } else {
                VStack(spacing: 12) {
                    ForEach(files) { file in
                        fileRow(for: file)
                            .obsCardStyleV2()
                    }
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("Keine Fahrtauszeichnung gefunden")
                .font(.obsSectionTitle)

            Text("Erstelle eine Fahrtauszeichnung. Danach erscheinen deine .bin- oder .csv-Dateien hier zum Teilen oder Hochladen.")
                .font(.obsFootnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func fileRow(for file: OBSFileInfo) -> some View {
        let metaLine = "\(file.sizeDescription) · \(file.dateDescription)"

        var statsParts: [String] = []
        if let count = file.overtakeCount { statsParts.append("\(count) Überholvorgänge") }
        if let km = file.distanceKm { statsParts.append("\(String(format: "%.2f", km)) km") }
        let statsLine = statsParts.joined(separator: " · ")

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(file.name)
                    .font(.obsBody.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metaLine)
                    .font(.obsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if !statsLine.isEmpty {
                    Text(statsLine)
                        .font(.obsCaption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(for: file))

            Spacer()

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
                .disabled(isUploading || !portalConfigured)

                Button(role: .destructive) {
                    pendingDeleteFile = file
                    isShowingDeleteConfirm = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            pendingUploadFile = file
            isShowingUploadConfirm = true
        }
    }

    // =====================================================
    // MARK: - Dateien laden / teilen / upload / löschen
    // =====================================================

    private func loadFiles() {
        let fm = FileManager.default

        do {
            let docs = try fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

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
                files = []
                return
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            var found: [OBSFileInfo] = []

            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "bin" || ext == "csv" else { continue }

                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isRegularFile == true else { continue }

                    let size = values.fileSize.map { formatBytes($0) } ?? "–"
                    let date = values.contentModificationDate
                    let dateDesc = date.map { formatter.string(from: $0) } ?? "–"

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

    private func share(_ file: OBSFileInfo) {
        let fm = FileManager.default

        do {
            let tempDir = fm.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(file.name)

            if fm.fileExists(atPath: tempURL.path) {
                try fm.removeItem(at: tempURL)
            }

            try fm.copyItem(at: file.url, to: tempURL)

            shareURL = tempURL
            isShowingShareSheet = true
        } catch {
            print("DataExportView: Fehler beim Vorbereiten der Datei zum Teilen: \(error)")
        }
    }

    private func upload(_ file: OBSFileInfo) {
        guard portalConfigured else {
            uploadStatusMessage = "Bitte im Portal-Bereich Portal-URL und API-Key eintragen."
            isShowingUploadResultAlert = true
            return
        }

        // Vorherigen Upload-Task abbrechen falls noch aktiv
        uploadTask?.cancel()

        isUploading = true

        uploadTask = Task {
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

    private func delete(_ file: OBSFileInfo) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: file.url)
            loadFiles()
        } catch {
            print("DataExportView: Fehler beim Löschen von \(file.url): \(error)")
        }
    }

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

    private func formatBytes(_ bytes: Int) -> String {
        let b = Double(bytes)
        if b < 1024 { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.2f MB", mb)
    }

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
