import SwiftUI

/// Gemeinsamer Screen-Wrapper für den wiederholten "Settings-/Grouped"-Look.
///
/// Zweck:
/// - Verhindert duplizierten UI-Code in mehreren Screens
/// - Gibt allen Screens denselben Hintergrund + Scroll-Verhalten + Padding
///
/// Funktional identisch zu:
/// ZStack(background) + ScrollView + Padding + hidden scroll indicators.
struct GroupedScrollScreen<Content: View>: View {

    /// Der Inhalt, der innerhalb des ScrollViews gerendert wird.
    /// @ViewBuilder erlaubt mehrere Views ohne extra Container (z.B. VStack) an der Aufrufstelle.
    @ViewBuilder let content: Content

    var body: some View {
        // ZStack, damit der Hintergrund unter dem ScrollView liegt
        ZStack {
            // iOS-typischer Hintergrund für gruppierte Einstellungen/Listen
            Color(.systemGroupedBackground)
                .ignoresSafeArea() // bis in Safe Areas (Notch/Home Indicator) zeichnen

            // ScrollView, damit Inhalte auf kleinen Geräten nicht abgeschnitten werden
            ScrollView {
                // Inhalt wird mit einheitlichen Abständen gerendert
                content
                    .padding(.horizontal, 16) // links/rechts Abstand
                    .padding(.top, 16)        // oben Abstand
                    .padding(.bottom, 32)     // unten extra Abstand (z.B. für Home Indicator)
            }
            // Scroll-Indikatoren ausblenden (optisch cleaner)
            .scrollIndicators(.hidden)
        }
    }
}

/// Gemeinsame Dauerformatierung (entspricht exakt der bisherigen Logik).
///
/// Erwartet Sekunden und gibt einen kurzen, lesbaren Text zurück:
/// - >= 1 Stunde: "X h Y min"
/// - < 1 Stunde:  "Y min"
enum DurationText {

    /// Formatiert eine Dauer in Sekunden in ein kompaktes Anzeigeformat.
    static func format(_ seconds: Double) -> String {
        // Sekunden in Int umwandeln (Nachkommastellen werden abgeschnitten)
        let s = Int(seconds)

        // Ganze Stunden berechnen
        let hours = s / 3600

        // Minutenrest innerhalb der aktuellen Stunde berechnen
        let minutes = (s % 3600) / 60

        // Ausgabe abhängig davon, ob mindestens eine Stunde vorhanden ist
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
}

/// Helper für Optional<String> ohne Force-Unwrap.
///
/// Beispiel:
/// - `track.title.obsDisplayText(or: "(ohne Titel)")`
/// - Gibt Fallback zurück, wenn nil/leer/nur Whitespaces.
extension Optional where Wrapped == String {

    /// Liefert den String zurück, wenn er existiert und nach Trim nicht leer ist,
    /// sonst den Fallback (Standard: "–").
    func obsDisplayText(or fallback: String = "–") -> String {
        // nil oder nach Trim leer? -> Fallback
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return fallback }

        // ansonsten den bereinigten String zurückgeben
        return s
    }
}
