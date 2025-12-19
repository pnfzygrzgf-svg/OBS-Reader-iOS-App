// PortalLoginView.swift
import SwiftUI

/// Zeigt eine Login-Seite des OBS-Portals in einer WebView an.
/// - `baseUrl`: Basis-URL des Portals (z.B. https://portal.openbikesensor.org)
/// - `onFinished`: Callback, der beim Tippen auf „Fertig“ ausgeführt wird (z.B. um nach dem Login weiterzumachen)
struct PortalLoginView: View {

    // Basis-URL wird von außen übergeben (z.B. aus den Einstellungen oder einem Parent-View)
    let baseUrl: String

    // Callback, den der Aufrufer bereitstellt (wird nach Cookie-Sync und vor dem Schließen ausgeführt)
    let onFinished: () -> Void

    // Environment-Wert zum Schließen (dismiss) der aktuellen Präsentation (Sheet/Navigation)
    @Environment(\.dismiss) private var dismiss

    /// Erzeugt aus `baseUrl` eine konkrete Login-URL (…/login).
    /// - Nutzung von URLComponents verhindert einfache String-Fehler und validiert die URL.
    /// - `components.path` ersetzt/setzt den Pfad auf "/login".
    private var loginURL: URL? {
        // baseUrl muss eine gültige URL sein, sonst nil
        guard var components = URLComponents(string: baseUrl) else { return nil }

        // Pfad auf Login setzen (führt zu https://.../login)
        components.path = "/login"

        // Fertige URL zurückgeben
        return components.url
    }

    var body: some View {
        // Bewusst weiterhin NavigationView:
        // - Das hält das bisherige Navigations-/Toolbar-Verhalten stabil
        // - Falls das View z.B. als Sheet präsentiert wird, passt das häufig gut
        NavigationView {
            Group {
                // Wenn die Login-URL gültig ist: WebView anzeigen
                if let loginURL {
                    PortalLoginWebView(url: loginURL)
                        // Titel oben in der NavBar
                        .navigationTitle("Portal-Login")
                        // Inline, damit es kompakt bleibt
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    // Fallback, wenn baseUrl ungültig ist
                    Text("Ungültige Portal-URL")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            // Toolbar gilt für beide Zustände (WebView oder Fehlertext)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // „Fertig“ beendet den Login-Flow
                    Button("Fertig") {
                        // Cookies aus der WebView (WKWebsiteDataStore / HTTPCookieStorage)
                        // in die URLSession-Welt synchronisieren, damit API-Requests danach authentifiziert sind.
                        syncCookiesToURLSession {
                            // Aufrufer informieren, dass der Flow fertig ist
                            onFinished()

                            // View schließen (z.B. Sheet dismissen)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    // Preview mit Beispiel-URL; Callback macht hier nichts
    PortalLoginView(baseUrl: "https://portal.openbikesensor.org") { }
}
