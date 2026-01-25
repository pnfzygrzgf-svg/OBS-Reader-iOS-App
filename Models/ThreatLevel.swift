import SwiftUI

/// Bedrohungsstufen für Überholvorgänge (4-Stufen-Skala)
enum ThreatLevel: Int, Codable, CaseIterable, Identifiable {
    case safe = 1           // Sicher - Entspanntes Weiterfahren
    case uncomfortable = 2  // Unbehaglich - Etwas zu nah/schnell
    case threatening = 3    // Bedrohlich - Deutlich zu knapp, Erschrecken
    case dangerous = 4      // Gefährlich - Notbremsung, Ausweichen, Fast-Sturz

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .safe: return "Sicher"
        case .uncomfortable: return "Unbehaglich"
        case .threatening: return "Bedrohlich"
        case .dangerous: return "Gefährlich"
        }
    }

    var description: String {
        switch self {
        case .safe: return "Entspanntes Weiterfahren"
        case .uncomfortable: return "Etwas zu nah/schnell"
        case .threatening: return "Deutlich zu knapp, Erschrecken"
        case .dangerous: return "Notbremsung, Ausweichen, Fast-Sturz"
        }
    }

    var color: Color {
        switch self {
        case .safe: return .obsGoodV2
        case .uncomfortable: return .obsWarnV2
        case .threatening: return .orange
        case .dangerous: return .obsDangerV2
        }
    }
}
