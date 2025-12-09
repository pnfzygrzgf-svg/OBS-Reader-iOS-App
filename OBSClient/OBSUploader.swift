// OBSUploader.swift

import Foundation

/// Ergebnis eines Upload-Versuchs.
/// Kapselt HTTP-Statuscode und Text-Antwort des Servers.
struct OBSUploadResult {
    let statusCode: Int
    let responseBody: String

    /// Wurde der Upload aus HTTP-Sicht erfolgreich (2xx)?
    var isSuccessful: Bool {
        (200...299).contains(statusCode)
    }
}

/// Verantwortlich für das Hochladen von OBS-Track-Dateien (.bin) zum Server.
///
/// - Implementiert einen `multipart/form-data` POST-Request,
///   der dem Java-Client entspricht (Part-Name: `"body"`).
/// - Authentifizierung per Header: `Authorization: OBSUserId <apiKey>`
final class OBSUploader {
    /// Singleton-Instanz für bequemen Zugriff.
    static let shared = OBSUploader()
    private init() {}

    /// Mögliche Fehler beim Aufbau/Ausführen des Requests (nicht Server-Fehlercodes).
    enum UploadError: Error {
        case invalidURL       // Base-URL oder zusammengesetzte URL war ungültig
        case noHTTPResponse   // URLSession hat keine HTTPURLResponse geliefert
    }

    /// Lädt eine Track-Datei als multipart/form-data zum OBS-Server hoch.
    ///
    /// Entspricht dem Java-Code:
    /// - POST
    /// - multipart/form-data
    /// - Part-Name: "body"
    /// - Authorization: "OBSUserId <apiKey>"
    ///
    /// - Parameters:
    ///   - fileURL: Lokale URL zur .bin-Datei, die hochgeladen werden soll.
    ///   - baseUrl: Basis-URL des OBS-Portals (z. B. "https://example.com" oder bereits mit "/api/tracks").
    ///   - apiKey: API-Key/User-ID für den Server (wird im Authorization-Header verwendet).
    ///
    /// - Returns: `OBSUploadResult` mit HTTP-Statuscode und Antwort-Body als String.
    /// - Throws: `UploadError` (z. B. invalidURL/noHTTPResponse) oder Fehler von `Data(contentsOf:)` / `URLSession`.
    func uploadTrack(fileURL: URL, baseUrl: String, apiKey: String) async throws -> OBSUploadResult {
        // Basis-URL ggf. auf /api/tracks ergänzen
        let urlString = normalizeObsUrl(baseUrl)
        guard let url = URL(string: urlString) else {
            throw UploadError.invalidURL
        }

        // Dateiinhalt in den Speicher laden (für große Dateien ggf. optimierbar)
        let fileData = try Data(contentsOf: fileURL)

        // Multipart-Boundary eindeutig machen
        let boundary = "Boundary-\(UUID().uuidString)"

        // HTTP-Request konfigurieren
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // OBS-spezifischer Authorization-Header
        request.setValue("OBSUserId \(apiKey)", forHTTPHeaderField: "Authorization")
        // multipart/form-data inkl. Boundary
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Body manuell als multipart/form-data zusammenbauen
        var body = Data()
        let lineBreak = "\r\n"

        // --boundary
        body.append("--\(boundary)\(lineBreak)")
        // Content-Disposition: form-data; name="body"; filename="..."
        body.append("Content-Disposition: form-data; name=\"body\"; filename=\"\(fileURL.lastPathComponent)\"\(lineBreak)")
        // Content-Type des Files (generisch als Binärdaten)
        body.append("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)")
        // tatsächlicher Dateiinhalt
        body.append(fileData)
        body.append(lineBreak)
        // Abschluss-Boundary: --boundary--
        body.append("--\(boundary)--\(lineBreak)")

        request.httpBody = body

        // Request asynchron senden
        let (data, response) = try await URLSession.shared.data(for: request)

        // Sicherstellen, dass es sich um eine HTTP-Antwort handelt
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.noHTTPResponse
        }

        // Antwort-Body als String (falls möglich)
        let responseBody = String(data: data, encoding: .utf8) ?? ""

        return OBSUploadResult(
            statusCode: httpResponse.statusCode,
            responseBody: responseBody
        )
    }

    /// Ergänzt die Basis-URL so, dass sie auf `/api/tracks` endet.
    ///
    /// Entspricht `normalizeObsUrl()` aus dem Java-Client:
    /// - Wenn `baseUrl` bereits mit `/api/tracks` oder `/api/tracks/` endet -> unverändert zurückgeben.
    /// - Sonst `/api/tracks` (mit oder ohne Slash dazwischen) anhängen.
    private func normalizeObsUrl(_ baseUrl: String) -> String {
        var url = baseUrl

        // Bereits vollständig?
        if !(url.hasSuffix("/api/tracks") || url.hasSuffix("/api/tracks/")) {
            if url.hasSuffix("/") {
                url += "api/tracks"
            } else {
                url += "/api/tracks"
            }
        }
        return url
    }
}

// MARK: - Data convenience

/// Kleine Helfer-Erweiterung, um String bequem an Data anzuhängen.
private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) {
            append(d)
        }
    }
}
