// PortalLoginWebView.swift

import SwiftUI
import WebKit

/// SwiftUI-Wrapper um `WKWebView`, damit eine WebView in SwiftUI verwendet werden kann.
/// Wird hier genutzt, um den Portal-Login im eingebetteten Browser anzuzeigen.
struct PortalLoginWebView: UIViewRepresentable {

    /// Die URL, die beim Erstellen der WebView geladen werden soll (z.B. https://.../login)
    let url: URL

    /// Erzeugt und konfiguriert die UIKit-View (WKWebView) genau einmal.
    /// SwiftUI ruft diese Methode auf, wenn die View erstmals benötigt wird.
    func makeUIView(context: Context) -> WKWebView {
        // Konfiguration der WebView (Cookies, Speicher, Prozesse, etc.)
        let config = WKWebViewConfiguration()

        // Default Data Store:
        // - nutzt den normalen persistenten Cookie-/Website-Speicher
        // - wichtig, damit Login-Cookies erhalten bleiben
        config.websiteDataStore = .default()

        // WKWebView mit obiger Konfiguration erstellen
        let webView = WKWebView(frame: .zero, configuration: config)

        // Request bauen und initiale URL laden
        webView.load(URLRequest(url: url))

        return webView
    }

    /// Wird von SwiftUI aufgerufen, wenn sich SwiftUI-State ändert und die UIKit-View aktualisiert werden soll.
    /// In dieser einfachen Variante ist kein Update nötig, weil:
    /// - wir nur eine Start-URL laden
    /// - und keine weiteren Bindings/States synchronisieren
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // nichts nötig
        // (wenn du später z.B. eine neue URL laden willst, könntest du hier prüfen:
        //  if uiView.url != url { uiView.load(URLRequest(url: url)) })
    }
}
