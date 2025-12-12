// CookieSync.swift

import Foundation
import WebKit

/// Kopiert alle Cookies aus dem WKWebView-Speicher
/// in die globale URLSession-Cookie-Storage.
func syncCookiesToURLSession(completion: @escaping () -> Void) {
    let dataStore = WKWebsiteDataStore.default()
    dataStore.httpCookieStore.getAllCookies { cookies in
        let cookieStorage = HTTPCookieStorage.shared

        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }

        // Debug: einmal schauen, welche Cookies URLSession sieht
        print("🍪 [CookieSync] Cookies in HTTPCookieStorage.shared:")
        for cookie in cookieStorage.cookies ?? [] {
            print("  - \(cookie.name) | domain=\(cookie.domain) | path=\(cookie.path)")
        }

        completion()
    }
}
