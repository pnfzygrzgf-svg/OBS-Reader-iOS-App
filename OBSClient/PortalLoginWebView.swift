import SwiftUI
import WebKit

/// Einfache WKWebView, die die Login-URL des Portals lädt.
struct PortalLoginWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // gemeinsamer Cookie-Store

        let webView = WKWebView(frame: .zero, configuration: config)
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // nichts nötig
    }
}
