import SwiftUI

struct PortalLoginView: View {
    let baseUrl: String
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Baut die Login-URL:
    /// Laut Backend-Konfig:
    /// - apiUrl = <baseUrl>/api
    /// - loginUrl = <baseUrl>/login
    /// Für den Login benutzen wir also <baseUrl>/login.
    private var loginURL: URL? {
        guard var components = URLComponents(string: baseUrl) else { return nil }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/login"
        return components.url
    }

    var body: some View {
        NavigationView {
            Group {
                if let loginURL {
                    PortalLoginWebView(url: loginURL)
                        .navigationTitle("Portal-Login")
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    Text("Ungültige Portal-URL")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        // Cookies aus dem WebView in URLSession kopieren
                        syncCookiesToURLSession {
                            onFinished()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    PortalLoginView(baseUrl: "https://portal.openbikesensor.org") { }
}

