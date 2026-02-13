// OBSConstants.swift

import SwiftUI
import UIKit

// =====================================================
// MARK: - Overtake Distance Thresholds
// =====================================================

/// Schwellenwerte für die Farbcodierung von Überholabständen (in Metern)
enum OBSOvertakeThresholds {
    /// Kritisch nah (Rot) - unter 1.10m
    static let critical: Double = 1.10
    /// Warnung (Orange) - unter 1.30m
    static let warning: Double = 1.30
    /// Vorsicht (Gelb) - unter 1.50m
    static let caution: Double = 1.50
    /// Sicher (Grün) - unter 1.70m
    static let safe: Double = 1.70

    /// Gibt die passende UIColor für einen Überholabstand zurück (für MapKit)
    static func uiColor(for distance: Double) -> UIColor {
        switch distance {
        case ...critical:
            return .systemRed
        case ...warning:
            return .systemOrange
        case ...caution:
            return .systemYellow
        case ...safe:
            return .systemGreen
        default:
            return UIColor.systemGreen.withAlphaComponent(0.8)
        }
    }

    /// Gibt die passende SwiftUI Color für einen Überholabstand zurück
    static func color(for distance: Double) -> Color {
        switch distance {
        case ...critical:
            return Color.obsDangerV2
        case ...warning:
            return Color.obsWarnV2
        case ...caution:
            return Color.yellow
        case ...safe:
            return Color.obsGoodV2
        default:
            return Color.obsGoodV2.opacity(0.8)
        }
    }
}

// =====================================================
// MARK: - Timing Constants
// =====================================================

/// Zentrale Timing-Konstanten für Animationen und Delays
enum OBSTiming {
    /// Dauer für Toast-Anzeige (z.B. Speicherbestätigung)
    static let toastDuration: TimeInterval = 2.0
    /// Splash-Screen Anzeigedauer
    static let splashDuration: TimeInterval = 2.0
    /// Delay vor Reconnect-Versuch
    static let reconnectDelay: TimeInterval = 1.0
    /// Timeout für Sensor-Watchdog (UI-seitig)
    static let sensorTimeout: TimeInterval = 5.0
    /// Delay bevor Hinweis ausgeblendet wird
    static let hintHideDelay: TimeInterval = 1.2
    /// Kurzes Debounce-Delay
    static let debounceDelay: TimeInterval = 0.5
}

// =====================================================
// MARK: - Corner Radius
// =====================================================

/// Einheitliche Eckenradien
enum OBSCornerRadius {
    /// Klein (4pt) - für kleine Elemente
    static let small: CGFloat = 4
    /// Standard (12pt) - für Cards
    static let medium: CGFloat = 12
    /// Groß (16pt) - für große Cards/Buttons
    static let large: CGFloat = 16
    /// Pill/Capsule Form
    static let pill: CGFloat = 999
}

// =====================================================
// MARK: - Shadow Presets
// =====================================================

/// Vordefinierte Schatten-Konfigurationen
enum OBSShadow {
    /// Subtiler Schatten für Cards
    static let cardRadius: CGFloat = 2
    static let cardX: CGFloat = 0
    static let cardY: CGFloat = 1
    static let cardOpacity: Double = 0.04

    /// Standard-Schatten für Buttons/Overlays
    static let standardRadius: CGFloat = 4
}
