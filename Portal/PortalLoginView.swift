// PortalLoginView.swift

import SwiftUI

/// Zeigt eine Login-Seite des OBS-Portals in einer WebView an.
/// - `baseUrl`: Basis-URL des Portals (z.B. https://portal.openbikesensor.org)
/// - `onFinished`: Callback, der beim Tippen auf „Fertig“ ausgeführt wird (z.B. um nach dem Login weiterzumachen)
///
/// OPTIK-UPDATE:
/// - NavigationStack (modern)
/// - klare Fehlerkarte statt nur roter Text
///
/// TECH-FIX:
/// - keine Verwendung von OBSSectionHeader (alt), sondern V2 (verhindert „Ambiguous init“)
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
        NavigationStack {
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
                    ZStack {
                        Color(.systemGroupedBackground).ignoresSafeArea()

                        invalidUrlCard
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    .navigationTitle("Portal-Login")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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

    /// Schöne Fehlerkarte, falls baseUrl ungültig ist.
    private var invalidUrlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                OBSSectionHeaderV2("Ungültige Portal-URL")
            }

            Text("Bitte prüfe in den Portal-Einstellungen die Portal-URL (inkl. https://).")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)

            Text("Aktuell: \(baseUrl)")
                .font(.obsCaption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .obsCardStyleV2()
    }
}

#Preview {
    // Preview mit Beispiel-URL; Callback macht hier nichts
    PortalLoginView(baseUrl: "https://portal.openbikesensor.org") { }
}
