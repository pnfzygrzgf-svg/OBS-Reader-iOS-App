// OBSUIV2.swift

import SwiftUI
import Foundation

// =====================================================
// MARK: - Theme Colors (V2) – redeclaration-sicher
// =====================================================

/// Zentrale Theme-Farben aus Assets.
/// Vorteil: Keine Kollisionen mit evtl. vorhandenen `extension Color` Properties.
enum OBSThemeV2 {
    static let accent = Color("OBSAccent")

    static let card = Color("OBSCard")
    static let cardBorder = Color("OBSCardBorder")

    static let good = Color("OBSGood")
    static let warn = Color("OBSWarn")
    static let danger = Color("OBSDanger")
}

/// Optional: V2-Properties, damit du kurz schreiben kannst (`.obsAccentV2`)
/// Diese Namen sind bewusst neu (V2-Suffix), damit es garantiert nicht kollidiert.
extension Color {
    static var obsAccentV2: Color { OBSThemeV2.accent }
    static var obsCardV2: Color { OBSThemeV2.card }
    static var obsCardBorderV2: Color { OBSThemeV2.cardBorder }
    static var obsGoodV2: Color { OBSThemeV2.good }
    static var obsWarnV2: Color { OBSThemeV2.warn }
    static var obsDangerV2: Color { OBSThemeV2.danger }

    /// App-spezifische Farblogik (Überholabstand) – nutzt Theme-Farben
    static func obsOvertakeColorV2(for distance: Int) -> Color {
        switch distance {
        case ..<100:      return .obsDangerV2
        case 100..<150:   return .obsWarnV2
        default:          return .obsGoodV2
        }
    }
}

// =====================================================
// MARK: - Card Style V2
// =====================================================

/// Einheitlicher "Card"-Look (V2) – Performance-freundlich
///
/// WICHTIG:
/// `.overlay(...)` und `.background(...)` können sonst Touches "wegfangen",
/// wodurch Buttons/NavigationLinks innerhalb der Card nicht mehr klickbar sind.
/// Daher: `allowsHitTesting(false)` für Deko-Layer.
struct OBSCardStyleV2: ViewModifier {

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.obsCardV2)
                    .allowsHitTesting(false) // ✅ verhindert Tap-Blocking
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.obsCardBorderV2.opacity(0.75), lineWidth: 1)
                    .allowsHitTesting(false) // ✅ verhindert Tap-Blocking
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func obsCardStyleV2() -> some View {
        modifier(OBSCardStyleV2())
    }
}

// =====================================================
// MARK: - Grouped Scroll Screen V2
// =====================================================

struct GroupedScrollScreenV2<Content: View>: View {

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(.vertical) {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

// =====================================================
// MARK: - Components V2
// =====================================================

struct OBSSectionHeaderV2: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.obsScreenTitle)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OBSStatusChipV2: View {
    enum Style {
        case success
        case warning
        case danger
        case neutral

        var foreground: Color {
            switch self {
            case .success: return .obsGoodV2
            case .warning: return .obsWarnV2
            case .danger:  return .obsDangerV2
            case .neutral: return .secondary
            }
        }

        var background: Color {
            switch self {
            case .success: return Color.obsGoodV2.opacity(0.15)
            case .warning: return Color.obsWarnV2.opacity(0.15)
            case .danger:  return Color.obsDangerV2.opacity(0.15)
            case .neutral: return Color.secondary.opacity(0.12)
            }
        }
    }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.obsCaption.weight(.semibold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(style.background)
            )
    }
}

struct OBSRowCardV2: View {
    let icon: String
    let title: String
    let subtitle: String?

    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsSectionTitle)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// =====================================================
// MARK: - Distance Formatter V2
// =====================================================

enum OBSDistanceFormatterV2 {
    static func kmString(fromMeters meters: Double) -> String {
        let km = meters / 1000.0
        return km.formatted(.number.precision(.fractionLength(2)))
    }
}

// =====================================================
// MARK: - Optional String helpers V2
// =====================================================

extension Optional where Wrapped == String {

    var obsNonEmptyOrDashV2: String {
        guard let s = self,
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "-" }
        return s
    }
}
