import Foundation

/// Sehr einfacher Test: ruft GET <baseUrl>/api/tracks?limit=2 auf
/// und druckt die Antwort als String in die Konsole.
func portalApiPrintTracks(baseUrl: String) async {
    // 1) Basis-URL in URLComponents packen
    guard var components = URLComponents(string: baseUrl) else {
        print("PortalTest: ungültige Basis-URL: \(baseUrl)")
        return
    }

    // 2) Pfad erweitern: /api/tracks
    // vorhandenen Pfad berücksichtigen
    let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
    components.path = basePath + "/api/tracks"

    // 3) Query-Parameter limit=2
    components.queryItems = [
        URLQueryItem(name: "limit", value: "2"),
    ]

    guard let url = components.url else {
        print("PortalTest: konnte URL nicht bauen")
        return
    }

    print("PortalTest: rufe URL auf: \(url.absoluteString)")

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            print("PortalTest: keine HTTP-Antwort")
            return
        }

        print("PortalTest: Status = \(http.statusCode)")

        let body = String(data: data, encoding: .utf8) ?? "<keine UTF-8-Daten>"
        print("PortalTest: Antwort-Body:\n\(body)")
    } catch {
        print("PortalTest: Fehler beim Request: \(error)")
    }
}
