// FontOBS.swift

import SwiftUI

// MARK: - Basis-Helfer für OBS-Fonts

extension Font {
    /// Rounded-Systemfont für einen gegebenen TextStyle (headline, body, caption, …)
    /// - Parameter style: Der dynamische TextStyle (passt sich an Dynamic Type an)
    /// - Parameter weight: Schriftgewicht (Standard: .regular)
    ///
    /// Nutzung:
    ///   Text("Hallo").font(.obs(.body, weight: .medium))
    static func obs(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    /// Rounded-Systemfont mit fester Punktgröße.
    /// - Parameter size: Schriftgröße in Punkten
    /// - Parameter weight: Schriftgewicht (Standard: .regular)
    ///
    /// Nutzung:
    ///   Text("Wert").font(.obs(size: 24, weight: .bold))
    static func obs(size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - App-eigene Typo-Rollen
// Semantische Aliase, damit im restlichen Code nicht überall „magische“ Größen stehen,
// sondern sprechende Rollen wie .obsScreenTitle, .obsBody, etc.

extension Font {
    /// Titel oben im Screen (z.B. „Messwerte“, „Fahrtaufzeichnungen“)
    /// Relativ groß und fett für prominente Überschriften.
    static var obsScreenTitle: Font {
        .obs(size: 24, weight: .bold)
    }

    /// Abschnittsüberschrift (z.B. „Sensor links“, „Fahrtaufzeichnungen“)
    /// Etwas kleiner als Screen-Titel, aber hervorgehoben.
    static var obsSectionTitle: Font {
        .obs(.headline, weight: .semibold)
    }

    /// Standard-Text für Fließtexte und Beschreibungen.
    static var obsBody: Font {
        .obs(.body)
    }

    /// Kleinere Zusatzinfos (z.B. rechtliche Hinweise, kurze Untertitel).
    static var obsFootnote: Font {
        .obs(.footnote)
    }

    /// Kleine Meta-Infos (Dateigröße, Datum, Hinweise etc.).
    static var obsCaption: Font {
        .obs(.caption)
    }

    /// Werte-Anzeige (Sensorwerte, Distanzen, wichtige Zahlen).
    /// Etwas größer und halb-fett, damit Zahlen hervorstechen.
    static var obsValue: Font {
        .obs(size: 18, weight: .semibold)
    }
}
