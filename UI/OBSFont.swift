// OBSFont.swift

import SwiftUI

// =====================================================
// MARK: - Basis-Helfer für OBS-Fonts
// =====================================================

extension Font {

    /// Erzeugt eine System-Schrift im „rounded“-Design für einen dynamischen TextStyle.
    ///
    /// Warum TextStyle?
    /// - `TextStyle` (z.B. `.body`, `.headline`, `.caption`) unterstützt **Dynamic Type**:
    ///   Wenn der Nutzer in iOS die Schriftgröße hochstellt, skaliert die Schrift automatisch mit.
    ///
    /// Warum design: .rounded?
    /// - Verleiht der UI eine „runde“, freundlichere Typografie (ähnlich SF Rounded).
    ///
    /// - Parameters:
    ///   - style: Dynamischer TextStyle (passt sich Dynamic Type an)
    ///   - weight: Schriftgewicht (Standard: `.regular`)
    ///
    /// Beispiel:
    /// `Text("Hallo").font(.obs(.body, weight: .medium))`
    static func obs(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    /// Erzeugt eine System-Schrift im „rounded“-Design mit fixer Punktgröße.
    ///
    /// Wann sinnvoll?
    /// - Für große Zahlendarstellungen oder feste Rollen, wo du eine konkrete Größe willst.
    ///
    /// Hinweis:
    /// - Fixe Größen skalieren *nicht* automatisch so flexibel wie TextStyles.
    ///   (Je nach Bedarf kann das trotzdem gewollt sein, z.B. bei großen Zahlen.)
    ///
    /// - Parameters:
    ///   - size: Schriftgröße in Punkten
    ///   - weight: Schriftgewicht (Standard: `.regular`)
    ///
    /// Beispiel:
    /// `Text("Wert").font(.obs(size: 24, weight: .bold))`
    static func obs(size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// =====================================================
// MARK: - App-eigene Typo-Rollen (semantische Aliase)
// =====================================================
//
// Idee:
// Statt im Code überall „magische Zahlen“ oder Styles zu verteilen,
// gibt es sprechende Rollen wie `.obsScreenTitle`, `.obsBody`, `.obsValue`.
// So bleibt das Design konsistent und Änderungen sind zentral möglich.
//
// OPTIK-UPDATE:
// - ScreenTitle etwas kleiner/ruhiger (passt besser zu iOS grouped screens)
// =====================================================

extension Font {

    /// Sehr prominenter Titel (z.B. Screen-Überschrift innerhalb einer Card).
    /// OPTIK: etwas kleiner und weniger „schreiend“
    static var obsScreenTitle: Font {
        .obs(size: 20, weight: .semibold)
    }

    /// Abschnittsüberschrift (z.B. „Sensorwerte“, „Lenkerbreite“).
    /// Etwas kleiner als ScreenTitle, aber immer noch klar hervorgehoben.
    static var obsSectionTitle: Font {
        .obs(.headline, weight: .semibold)
    }

    /// Standard-Fließtext für normale Inhalte.
    static var obsBody: Font {
        .obs(.body)
    }

    /// Kleinerer Text für Zusatzinfos/Erklärungen.
    static var obsFootnote: Font {
        .obs(.footnote)
    }

    /// Sehr kleiner Text für Meta-Infos (Dateigröße, Datum, kleine Labels).
    static var obsCaption: Font {
        .obs(.caption)
    }

    /// Hervorgehobene Zahlen/Werte (z.B. Sensor-Abstände).
    /// Größer + semibold, damit Zahlen gut lesbar sind.
    static var obsValue: Font {
        .obs(size: 18, weight: .semibold)
    }
}
