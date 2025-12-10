import SwiftUI
import UniformTypeIdentifiers

// MARK: - Helper: Speicherung der Überholvorgänge & Distanz pro Datei

/// Speichert Auswertungsdaten (Anzahl Überholvorgänge + Distanz) pro Aufnahmedatei
/// in `UserDefaults`, verknüpft über den Dateinamen (lastPathComponent).
struct OvertakeStatsStore {
    private static let countsKey   = "obsOvertakeCounts"
    private static let distanceKey = "obsTrackDistanceMeters"

    static func store(count: Int?, distanceMeters: Double?, for url: URL) {
        let fileKey = url.lastPathComponent

        if let count = count, count > 0 {
            var dict = (UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
            dict[fileKey] = count
            UserDefaults.standard.set(dict, forKey: countsKey)
        }

        if let meters = distanceMeters, meters > 0 {
            var dict = (UserDefaults.standard.dictionary(forKey: distanceKey) as? [String: Double]) ?? [:]
            dict[fileKey] = meters
            UserDefaults.standard.set(dict, forKey: distanceKey)
        }
    }

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

    let overtakeCount: Int?
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
struct DataExportView: View {

    @State private var files: [OBSFileInfo] = []

    // Sharing
    @State private var isShowingShareSheet = false
    @State private var shareURL: URL?

    // OBS-Portal-Einstellungen (aus zentraler Konfiguration)
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

    private var portalConfigured: Bool {
        !obsBaseUrl.isEmpty && !obsApiKey.isEmpty
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Nur Hinweis, falls Portal (noch) nicht konfiguriert ist.
                    if !portalConfigured {
                        portalHintCard
                            .obsCardStyle()
                    }

                    recordingsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
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
        .navigationTitle("Fahrtaufzeichnungen")
        .toolbar {
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
            loadFiles()
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

    // MARK: - Unterviews

    /// Hinweis, dass die eigentliche Konfiguration im Portal-Screen liegt.
    private var portalHintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Portal noch nicht eingerichtet")
                    .font(.obsSectionTitle)
            }

            Text("Um Fahrten direkt ins OBS-Portal hochzuladen, bitte im Bereich „Portal“ (Tab unten) die Portal-URL und den API-Key eintragen.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dateien")
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
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            pendingUploadFile = file
            isShowingUploadConfirm = true
        }
    }

    // MARK: - Dateien laden / teilen / upload / löschen

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
