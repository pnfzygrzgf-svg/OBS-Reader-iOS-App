// OBSEmptyStateView.swift

import SwiftUI

/// Einheitliche Empty-State-Komponente für leere Listen/Zustände
struct OBSEmptyStateView: View {
    /// SF Symbol Name für das Icon
    let icon: String
    /// Haupttitel
    let title: String
    /// Beschreibender Text
    let message: String
    /// Optionaler Button-Titel
    var actionTitle: String? = nil
    /// Optionale Button-Aktion
    var action: (() -> Void)? = nil
    /// Icon-Farbe (Standard: secondary)
    var iconColor: Color = .secondary
    /// Icon-Größe (Standard: 38pt)
    var iconSize: CGFloat = 38

    var body: some View {
        VStack(spacing: OBSSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)

            VStack(spacing: OBSSpacing.sm) {
                Text(title)
                    .font(.obsSectionTitle)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.obsFootnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(.obsPrimary)
                .padding(.top, OBSSpacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OBSSpacing.md)
    }
}

/// Variante mit Warning-Styling für Konfigurationsprobleme
struct OBSWarningStateView: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        OBSEmptyStateView(
            icon: "exclamationmark.triangle.fill",
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: action,
            iconColor: .orange
        )
    }
}

#Preview("Empty State") {
    OBSEmptyStateView(
        icon: "doc.text.magnifyingglass",
        title: "Keine Aufzeichnungen",
        message: "Starte eine Fahrt, um Aufzeichnungen zu erstellen."
    )
    .obsCardStyleV2()
    .padding()
}

#Preview("Empty State mit Action") {
    OBSEmptyStateView(
        icon: "bicycle",
        title: "Keine Tracks gefunden",
        message: "Prüfe ob du eingeloggt bist.",
        actionTitle: "Einloggen"
    ) {
        print("Login tapped")
    }
    .obsCardStyleV2()
    .padding()
}

#Preview("Warning State") {
    OBSWarningStateView(
        title: "Portal nicht konfiguriert",
        message: "Richte das Portal ein, um Fahrten hochzuladen."
    )
    .obsCardStyleV2()
    .padding()
}
