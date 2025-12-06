import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

struct OBSFileInfo: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let sizeDescription: String
    let dateDescription: String
}

// Wrapper für Share Sheet
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - View

struct DataExportView: View {

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

    // Bestätigung für Upload
    @State private var isShowingUploadConfirm: Bool = false
    @State private var pendingUploadFile: OBSFileInfo?

    // Bestätigung für Löschen (eine Datei oder alle)
    @State private var isShowingDeleteConfirm: Bool = false
    @State private var pendingDeleteFile: OBSFileInfo?

    var body: some View {
        ZStack {
            List {
                // OBS-Portal-Konfiguration
                Section("OBS-Portal") {
                    TextField("Basis-URL (z.B. https://meinserver)", text: $obsBaseUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    SecureField("API-Key", text: $obsApiKey)

                    if obsBaseUrl.isEmpty || obsApiKey.isEmpty {
                        Text("Bitte Basis-URL und API-Key eintragen, um hochladen zu können.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Dateien
                Section("Aufnahmen (.bin / .csv)") {
                    if files.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Keine Aufnahmen gefunden")
                                .font(.headline)
                            Text("Starte eine Aufnahme, dann erscheint hier eine .bin (und optional .csv), die du teilen, hochladen oder löschen kannst.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                    } else {
                        ForEach(files) { file in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                HStack(spacing: 12) {
                                    Text(file.sizeDescription)
                                    Text(file.dateDescription)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                HStack {
                                    Button {
                                        print("DataExportView: share() Button für \(file.name)")
                                        share(file)
                                    } label: {
                                        Label("Teilen / AirDrop", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.borderless)

                                    Button {
                                        print("DataExportView: upload() Button für \(file.name)")
                                        pendingUploadFile = file
                                        isShowingUploadConfirm = true
                                    } label: {
                                        Label("Hochladen", systemImage: "icloud.and.arrow.up")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(isUploading || obsBaseUrl.isEmpty || obsApiKey.isEmpty)

                                    Spacer()

                                    Button(role: .destructive) {
                                        print("DataExportView: delete() Button für \(file.name)")
                                        pendingDeleteFile = file
                                        isShowingDeleteConfirm = true
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .font(.caption)
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                            // Swipe-Actions
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    pendingDeleteFile = file
                                    isShowingDeleteConfirm = true
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
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
                            }
                        }
                    }
                }
            }
            .blur(radius: isUploading ? 1 : 0)

            if isUploading {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                ProgressView("Upload läuft…")
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
            }
        }
        .navigationTitle("Dateien (.bin / .csv)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    if !files.isEmpty {
                        pendingDeleteFile = nil   // nil => alle
                        isShowingDeleteConfirm = true
                    }
                } label: {
                    Label("Alle löschen", systemImage: "trash.slash")
                }
                .disabled(files.isEmpty)
                .buttonStyle(.borderless)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    loadFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Liste aktualisieren")
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            loadFiles()
        }
        // Share Sheet
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = shareURL {
                ActivityView(activityItems: [url])
            }
        }
        // Upload-Ergebnis-Alert (mit Dateinamen im Text)
        .alert("Upload", isPresented: $isShowingUploadResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uploadStatusMessage ?? "Unbekannter Fehler")
        }
        // Upload-Bestätigung
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
                Text("Die Datei „\(file.name)“ wird dauerhaft gelöscht.")
            } else {
                Text("Alle angezeigten Dateien werden dauerhaft gelöscht.")
            }
        }
    }

    // MARK: - Dateien laden (rekursiv im ganzen Documents-Ordner)

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

            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "bin" || ext == "csv" else { continue }

                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isRegularFile == true else { continue }

                    let size = values.fileSize.map { formatBytes($0) } ?? "–"
                    let date = values.contentModificationDate.map { formatter.string(from: $0) } ?? "–"

                    let info = OBSFileInfo(
                        url: url,
                        name: url.lastPathComponent,
                        sizeDescription: size,
                        dateDescription: date
                    )
                    found.append(info)
                } catch {
                    print("DataExportView: Attribute-Fehler für \(url.path): \(error)")
                }
            }

            print("DataExportView: gefunden \(found.count) .bin/.csv Dateien")
            files = found.sorted(by: { $0.name < $1.name })

        } catch {
            print("DataExportView: loadFiles error: \(error)")
            files = []
        }
    }

    // MARK: - Teilen

    /// Teilt eine KOPIE im tmp-Ordner (Original bleibt im Documents-Ordner)
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

    // MARK: - Helfer

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
}
