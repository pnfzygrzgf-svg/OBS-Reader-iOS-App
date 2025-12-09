import Foundation
import WebKit

/// Kopiert alle Cookies aus dem WKWebView-Speicher in die globale URLSession-Cookie-Storage.
func syncCookiesToURLSession(completion: @escaping () -> Void) {
    let dataStore = WKWebsiteDataStore.default()
    dataStore.httpCookieStore.getAllCookies { cookies in
        let cookieStorage = HTTPCookieStorage.shared
        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }
        completion()
    }
}
