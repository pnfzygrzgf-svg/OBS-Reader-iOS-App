// CookieSync.swift

import Foundation
import WebKit

/// Kopiert alle Cookies aus dem WKWebView-Speicher (WKHTTPCookieStore)
/// in die globale Cookie-Storage von URLSession (HTTPCookieStorage.shared).
///
/// Hintergrund:
/// - WKWebView verwaltet Cookies in einem eigenen Store (WKWebsiteDataStore / WKHTTPCookieStore).
/// - URLSession nutzt standardmäßig HTTPCookieStorage.shared.
/// - Wenn du nach einem WebView-Login API-Requests mit URLSession machst,
///   fehlen ohne Sync oft Session-/Auth-Cookies.
///
/// - Parameter completion: Wird aufgerufen, nachdem alle Cookies übernommen wurden.
func syncCookiesToURLSession(completion: @escaping () -> Void) {
    // Default-DataStore entspricht dem “normalen” persistenten WKWebView Speicher
    // (nicht dem ephemeral / private browsing Store).
    let dataStore = WKWebsiteDataStore.default()

    // Der CookieStore von WKWebView liefert alle aktuell bekannten Cookies asynchron.
    dataStore.httpCookieStore.getAllCookies { cookies in
        // Globale Cookie-Storage, die URLSession (in der Regel) verwendet.
        // Hinweis: Das ist processweit/shared und betrifft alle URLSession-Requests,
        // sofern Cookie-Handling nicht explizit deaktiviert wurde.
        let cookieStorage = HTTPCookieStorage.shared

        // Alle Cookies aus WKWebView in HTTPCookieStorage übernehmen.
        // Dadurch “sieht” URLSession danach dieselben Cookies (z.B. Session, CSRF, etc.).
        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }

        // Debug-Ausgabe: zeigt, welche Cookies jetzt in HTTPCookieStorage liegen.
        // Praktisch, um zu prüfen, ob Domain/Path stimmen und ob z.B. Session-Cookies da sind.
        print("🍪 [CookieSync] Cookies in HTTPCookieStorage.shared:")
        for cookie in cookieStorage.cookies ?? [] {
            print("  - \(cookie.name) | domain=\(cookie.domain) | path=\(cookie.path)")
        }

        // Callback: Signalisiert dem Aufrufer, dass der Sync abgeschlossen ist.
        // (Wichtig, weil getAllCookies asynchron ist.)
        completion()
    }
}
