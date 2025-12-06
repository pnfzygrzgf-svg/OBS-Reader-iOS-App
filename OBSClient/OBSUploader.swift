import Foundation

struct OBSUploadResult {
    let statusCode: Int
    let responseBody: String

    var isSuccessful: Bool {
        (200...299).contains(statusCode)
    }
}

final class OBSUploader {
    static let shared = OBSUploader()
    private init() {}

    enum UploadError: Error {
        case invalidURL
        case noHTTPResponse
    }

    /// Entspricht dem Java-Code: POST multipart/form-data mit Part "body"
    func uploadTrack(fileURL: URL, baseUrl: String, apiKey: String) async throws -> OBSUploadResult {
        let urlString = normalizeObsUrl(baseUrl)
        guard let url = URL(string: urlString) else {
            throw UploadError.invalidURL
        }

        let fileData = try Data(contentsOf: fileURL)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("OBSUserId \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let lineBreak = "\r\n"

        // --boundary
        body.append("--\(boundary)\(lineBreak)")
        // Content-Disposition
        body.append("Content-Disposition: form-data; name=\"body\"; filename=\"\(fileURL.lastPathComponent)\"\(lineBreak)")
        // Content-Type des Files
        body.append("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)")
        body.append(fileData)
        body.append(lineBreak)
        // --boundary-- (Ende)
        body.append("--\(boundary)--\(lineBreak)")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.noHTTPResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""
        return OBSUploadResult(statusCode: httpResponse.statusCode,
                               responseBody: responseBody)
    }

    /// Entspricht normalizeObsUrl() aus Java
    private func normalizeObsUrl(_ baseUrl: String) -> String {
        var url = baseUrl
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

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) {
            append(d)
        }
    }
}
