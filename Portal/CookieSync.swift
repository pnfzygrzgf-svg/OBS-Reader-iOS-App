// CookieSync.swift

import Foundation
import WebKit

/// Synchronisiert Cookies von WKWebView zu URLSession.
///
/// Zweck:
/// WKWebView und URLSession verwenden standardmäßig **verschiedene Cookie-Speicher**:
/// - WKWebView: `WKWebsiteDataStore.default().httpCookieStore`
/// - URLSession: `HTTPCookieStorage.shared`
///
/// Wenn du z.B. einen Login in einer WKWebView machst und danach API-Requests mit URLSession,
/// fehlen ohne diesen Sync oft wichtige Cookies (Session/Auth/CSRF), wodurch Requests fehlschlagen.
///
/// - Parameter completion: Wird aufgerufen, sobald alle Cookies kopiert wurden.
///   Wichtig, weil das Auslesen von WKWebView-Cookies asynchron passiert.
func syncCookiesToURLSession(completion: @escaping () -> Void) {

    // Der "default" DataStore ist der normale, persistente WKWebView-Speicher
    // (nicht der private/ephemeral Store).
    let dataStore = WKWebsiteDataStore.default()

    // Der WKHTTPCookieStore liefert alle Cookies asynchron über einen Callback.
    dataStore.httpCookieStore.getAllCookies { cookies in

        // HTTPCookieStorage.shared ist der globale Cookie-Speicher,
        // den URLSession standardmäßig nutzt (prozessweit).
        // Achtung: Das beeinflusst auch andere URLSession-Requests in deiner App,
        // sofern Cookie-Handling nicht explizit deaktiviert wurde.
        let cookieStorage = HTTPCookieStorage.shared

        // Jedes Cookie aus dem WKWebView Store in den URLSession-Store kopieren.
        // Danach kann URLSession dieselben Cookies mitsenden (z.B. Session-Cookie, CSRF, ...).
        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }

        // Debug: Ausgabe aller Cookies, die jetzt im URLSession-Store liegen.
        // Hilfreich, um zu prüfen:
        // - sind Cookies überhaupt vorhanden?
        // - stimmen domain/path?
        // - ist ein Session-Cookie dabei?
        print("🍪 [CookieSync] Cookies in HTTPCookieStorage.shared:")
        for cookie in cookieStorage.cookies ?? [] {
            print("  - \(cookie.name) | domain=\(cookie.domain) | path=\(cookie.path)")
        }

        // Wichtig: completion erst hier aufrufen, weil getAllCookies asynchron ist.
        // Der Aufrufer kann danach sicher URLSession-Requests starten.
        completion()
    }
}
