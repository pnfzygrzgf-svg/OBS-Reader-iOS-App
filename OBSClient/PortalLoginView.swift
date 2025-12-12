// PortalLoginView.swift

import SwiftUI

struct PortalLoginView: View {
    let baseUrl: String
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Baut die Login-URL:
    /// - apiUrl  = <origin>/api
    /// - loginUrl = <origin>/login
    /// Wir benutzen als "Portal-URL" immer nur das Origin (Scheme + Host),
    /// egal was in den Einstellungen im Pfad steht.
    private var loginURL: URL? {
        guard var components = URLComponents(string: baseUrl) else { return nil }
        components.path = "/login"   // Pfadanteile vom Input werden ignoriert
        return components.url
    }

    var body: some View {
        NavigationView {
            Group {
                if let loginURL {
                    // PortalLoginWebView ist in PortalLoginWebView.swift definiert
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
                        // syncCookiesToURLSession kommt aus CookieSync.swift
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
