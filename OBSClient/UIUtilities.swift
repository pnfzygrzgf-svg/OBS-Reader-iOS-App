import SwiftUI
import Foundation

// MARK: - Card Style (8)

/// Einheitlicher "Card"-Look für wiederverwendbare UI-Blöcke.
/// Wird z.B. für Settings-Karten, Listen-Items oder Info-Boxen genutzt.
struct ObsCardStyle: ViewModifier {

    /// Baut den eigentlichen Style:
    /// - Innenabstand
    /// - Hintergrund als abgerundetes Rechteck
    /// - Hintergrundfarbe passend zum System (hell/dunkel)
    func body(content: Content) -> some View {
        content
            .padding(16) // Padding innerhalb der Karte
            .background(
                // RoundedRectangle als Kartenhintergrund
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    // SecondarySystemBackground passt sich automatisch an Light/Dark Mode an
                    .fill(Color(.secondarySystemBackground))
            )
    }
}

/// Convenience-Extension, damit man nicht jedes Mal `modifier(ObsCardStyle())` schreiben muss.
extension View {

    /// Anwendung des Card-Styles auf jede beliebige View:
    /// `VStack { ... }.obsCardStyle()`
    func obsCardStyle() -> some View {
        modifier(ObsCardStyle())
    }
}

// MARK: - Distance formatting (3)

/// Helfer zur Formatierung von Distanzen.
/// Wird z.B. genutzt, um Meterwerte als Kilometer-String anzuzeigen.
enum DistanceFormatter {

    /// Gibt Kilometer als lokalisierten String mit genau 2 Nachkommastellen zurück.
    /// Beispiele:
    /// - DE: 1230 m -> "1,23"
    /// - EN: 1230 m -> "1.23"
    static func kmString(fromMeters meters: Double) -> String {
        let km = meters / 1000.0
        // Swift FormatStyle: lokalisiert + exakt 2 Nachkommastellen
        return km.formatted(.number.precision(.fractionLength(2)))
    }
}

// MARK: - Optional String helpers (4)

/// Erweiterung für Optional<String>, um nil/leer/whitespace sicher zu behandeln.
extension Optional where Wrapped == String {

    /// Gibt "-" zurück, wenn der String nil ist oder nach Trim leer ist,
    /// sonst den Original-String.
    ///
    /// Vorteil:
    /// - Keine Force-Unwraps
    /// - Einheitliches Fallback-Verhalten in der UI
    var nonEmptyOrDash: String {
        guard let s = self,
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "-" }
        return s
    }
}

// MARK: - Colors

extension Color {

    /// Farbcode für Überholabstände (als Int interpretiert, z.B. Zentimeter oder Millimeter je nach Datenquelle).
    ///
    /// Aktuelle Logik:
    /// - < 100  -> rot (kritisch)
    /// - 100..149 -> orange (grenzwertig)
    /// - >= 150 -> grün (ok)
    ///
    /// Hinweis:
    /// Die Einheiten sollten im Aufrufer klar definiert sein (z.B. cm),
    /// damit die Schwellenwerte korrekt interpretiert werden.
    static func overtakeColor(for distance: Int) -> Color {
        switch distance {
        case ..<100:      return .red
        case 100..<150:   return .orange
        default:          return .green
        }
    }
}
