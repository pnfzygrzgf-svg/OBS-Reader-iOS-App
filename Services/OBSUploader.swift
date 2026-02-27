// SPDX-License-Identifier: GPL-3.0-or-later

// OBSUploader.swift

import Foundation

// =====================================================
// MARK: - Upload Result
// =====================================================

/// Ergebnis eines Upload-Versuchs.
/// Kapselt HTTP-Statuscode und die Text-Antwort des Servers,
/// damit die UI bequem Erfolg/Fehler anzeigen kann.
struct OBSUploadResult {

    /// HTTP Statuscode (z.B. 200, 201, 400, 401, 500 ...)
    let statusCode: Int

    /// Antwort-Body des Servers (meist JSON oder Text)
    let responseBody: String

    /// True, wenn der Upload aus HTTP-Sicht erfolgreich war (Status 2xx).
    var isSuccessful: Bool {
        (200...299).contains(statusCode)
    }
}

// =====================================================
// MARK: - OBSUploader
// =====================================================

/// Verantwortlich für das Hochladen von OBS-Track-Dateien (.bin) zum OBS-Server.
///
/// Technischer Hintergrund:
/// - Das OBS-Portal erwartet einen `multipart/form-data` POST-Request.
/// - Der Dateipart heißt (wie beim Java-Client) **"body"**.
/// - Authentifizierung erfolgt über einen Custom-Header:
///   `Authorization: OBSUserId <apiKey>`
///
/// Design:
/// - Als Singleton (`shared`) implementiert, damit man es einfach überall aufrufen kann.
final class OBSUploader: NSObject {

    /// Singleton-Instanz für bequemen Zugriff.
    static let shared = OBSUploader()

    /// Private init verhindert, dass mehrere Instanzen erstellt werden.
    private override init() {
        super.init()
    }

    /// Callback für Upload-Fortschritt (0.0 - 1.0)
    private var progressHandler: ((Double) -> Void)?

    /// Continuation für async/await mit Delegate
    private var uploadContinuation: CheckedContinuation<(Data, URLResponse), Error>?

    // =====================================================
    // MARK: - Errors
    // =====================================================

    /// Fehler beim Aufbau/Ausführen des Requests (nicht Server-Fehlercodes).
    enum UploadError: Error {
        /// Base-URL oder zusammengesetzte URL war ungültig
        case invalidURL

        /// URLSession hat keine HTTPURLResponse geliefert (z.B. unerwarteter Response-Typ)
        case noHTTPResponse
    }

    // =====================================================
    // MARK: - Public API
    // =====================================================

    /// Lädt eine Track-Datei als multipart/form-data zum OBS-Server hoch.
    ///
    /// Entspricht dem Java-Client:
    /// - POST
    /// - multipart/form-data
    /// - Part-Name: "body"
    /// - Authorization: "OBSUserId <apiKey>"
    ///
    /// - Parameters:
    ///   - fileURL: Lokale URL zur `.bin` Datei, die hochgeladen werden soll.
    ///   - baseUrl: Basis-URL des OBS-Portals (z.B. "https://example.com")
    ///              oder bereits inkl. "/api/tracks".
    ///   - apiKey: API-Key/User-ID für den Server (landet im Authorization-Header).
    ///
    /// - Returns: OBSUploadResult mit HTTP-Statuscode und Antwort-Body.
    /// - Throws:
    ///   - UploadError.invalidURL / .noHTTPResponse
    ///   - File-Lesefehler (Data(contentsOf:))
    ///   - Netzwerkfehler (URLSession)
    func uploadTrack(fileURL: URL, baseUrl: String, apiKey: String) async throws -> OBSUploadResult {

        // 1) Basis-URL normalisieren, damit sie sicher auf /api/tracks zeigt.
        let urlString = normalizeObsUrl(baseUrl)
        guard let url = URL(string: urlString) else {
            throw UploadError.invalidURL
        }

        // 2) Datei komplett in den Speicher laden.
        // Hinweis: Für sehr große Dateien könnte man streaming nutzen,
        // aber für typische OBS-Tracks ist das oft ausreichend.
        let fileData = try Data(contentsOf: fileURL)

        // 3) Boundary erzeugen (muss pro Request eindeutig sein)
        let boundary = "Boundary-\(UUID().uuidString)"

        // 4) Request konfigurieren (Methode + Header)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // OBS-spezifische Auth: "OBSUserId <apiKey>"
        request.setValue("OBSUserId \(apiKey)", forHTTPHeaderField: "Authorization")

        // Content-Type für multipart inkl. boundary
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // 5) Multipart-Body zusammenbauen
        var body = Data()
        let lineBreak = "\r\n"

        // Start des File-Parts: --boundary
        body.append("--\(boundary)\(lineBreak)")

        // Part-Header: Name muss "body" heißen, filename setzen wir auf den Dateinamen
        body.append("Content-Disposition: form-data; name=\"body\"; filename=\"\(fileURL.lastPathComponent)\"\(lineBreak)")

        // Content-Type des Files: generisch binär
        body.append("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)")

        // File-Daten anhängen
        body.append(fileData)
        body.append(lineBreak)

        // Abschluss-Boundary: --boundary--
        body.append("--\(boundary)--\(lineBreak)")

        // Body dem Request zuweisen
        request.httpBody = body

        // 6) Request senden (async/await)
        let (data, response) = try await URLSession.shared.data(for: request)

        // 7) Response als HTTP prüfen
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.noHTTPResponse
        }

        // 8) Antwort-Body als String (UTF-8) dekodieren
        let responseBody = String(data: data, encoding: .utf8) ?? ""

        // 9) Ergebnisobjekt zurückgeben
        return OBSUploadResult(
            statusCode: httpResponse.statusCode,
            responseBody: responseBody
        )
    }

    // =====================================================
    // MARK: - Upload with Progress
    // =====================================================

    /// Lädt eine Track-Datei mit Fortschrittsanzeige hoch.
    ///
    /// - Parameters:
    ///   - fileURL: Lokale URL zur Datei
    ///   - baseUrl: Basis-URL des OBS-Portals
    ///   - apiKey: API-Key für den Server
    ///   - onProgress: Callback mit Upload-Fortschritt (0.0 - 1.0)
    ///
    /// - Returns: OBSUploadResult mit HTTP-Statuscode und Antwort-Body.
    func uploadTrack(
        fileURL: URL,
        baseUrl: String,
        apiKey: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> OBSUploadResult {

        // 1) Basis-URL normalisieren
        let urlString = normalizeObsUrl(baseUrl)
        guard let url = URL(string: urlString) else {
            throw UploadError.invalidURL
        }

        // 2) Datei laden
        let fileData = try Data(contentsOf: fileURL)

        // 3) Boundary erzeugen
        let boundary = "Boundary-\(UUID().uuidString)"

        // 4) Request konfigurieren
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("OBSUserId \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // 5) Multipart-Body zusammenbauen
        var body = Data()
        let lineBreak = "\r\n"
        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"body\"; filename=\"\(fileURL.lastPathComponent)\"\(lineBreak)")
        body.append("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)")
        body.append(fileData)
        body.append(lineBreak)
        body.append("--\(boundary)--\(lineBreak)")

        // 6) Upload mit Progress-Tracking
        self.progressHandler = onProgress

        let (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            self.uploadContinuation = continuation

            let session = URLSession(
                configuration: .default,
                delegate: self,
                delegateQueue: .main
            )

            let task = session.uploadTask(with: request, from: body) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: UploadError.noHTTPResponse)
                }
            }
            task.resume()
        }

        self.progressHandler = nil
        self.uploadContinuation = nil

        // 7) Response prüfen
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.noHTTPResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""

        return OBSUploadResult(
            statusCode: httpResponse.statusCode,
            responseBody: responseBody
        )
    }

    // =====================================================
    // MARK: - URL Normalisierung
    // =====================================================

    /// Ergänzt die Basis-URL so, dass sie auf `/api/tracks` endet.
    ///
    /// Beispiel:
    /// - "https://example.com"        -> "https://example.com/api/tracks"
    /// - "https://example.com/"       -> "https://example.com/api/tracks"
    /// - "https://example.com/api/tracks"  -> bleibt so
    /// - "https://example.com/api/tracks/" -> bleibt so
    private func normalizeObsUrl(_ baseUrl: String) -> String {
        var url = baseUrl

        // Falls die URL noch nicht auf /api/tracks endet, hängen wir es an.
        if !(url.hasSuffix("/api/tracks") || url.hasSuffix("/api/tracks/")) {
            // Wenn baseUrl schon mit / endet, ohne extra Slash anhängen
            if url.hasSuffix("/") {
                url += "api/tracks"
            } else {
                url += "/api/tracks"
            }
        }

        return url
    }
}

// =====================================================
// MARK: - URLSessionTaskDelegate (Progress Tracking)
// =====================================================

extension OBSUploader: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        progressHandler?(progress)
    }
}

// =====================================================
// MARK: - Data convenience
// =====================================================

/// Kleine Helfer-Erweiterung, um Strings bequem an `Data` anzuhängen.
private extension Data {
    /// Wandelt den String in UTF-8 um und hängt die Bytes an `Data` an.
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) {
            append(d)
        }
    }
}
