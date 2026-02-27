// SPDX-License-Identifier: GPL-3.0-or-later

// OBSErrorCardView.swift

import SwiftUI

/// Inline-Fehlerkarte mit optionaler Retry-Aktion
struct OBSErrorCardView: View {
    /// Fehlernachricht
    let message: String
    /// Optionale Retry-Aktion
    var retryAction: (() -> Void)? = nil
    /// Optionaler Dismiss-Handler
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: OBSSpacing.lg) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.obsDangerV2)

            VStack(alignment: .leading, spacing: OBSSpacing.md) {
                Text("Fehler")
                    .font(.obsSectionTitle)

                Text(message)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if retryAction != nil || onDismiss != nil {
                    HStack(spacing: OBSSpacing.lg) {
                        if let retryAction {
                            Button {
                                retryAction()
                            } label: {
                                Label("Erneut versuchen", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.obsTertiary)
                        }

                        if let onDismiss {
                            Button {
                                onDismiss()
                            } label: {
                                Text("Schließen")
                            }
                            .buttonStyle(.obsTertiary)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, OBSSpacing.xs)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(OBSSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: OBSCornerRadius.medium, style: .continuous)
                .fill(Color.obsDangerV2.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OBSCornerRadius.medium, style: .continuous)
                .stroke(Color.obsDangerV2.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Inline-Warnungskarte (für nicht-kritische Probleme)
struct OBSWarningCardView: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: OBSSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: OBSSpacing.md) {
                Text(title)
                    .font(.obsSectionTitle)

                Text(message)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                    }
                    .buttonStyle(.obsTertiary)
                    .padding(.top, OBSSpacing.xs)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(OBSSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: OBSCornerRadius.medium, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OBSCornerRadius.medium, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview("Error Card") {
    VStack(spacing: 16) {
        OBSErrorCardView(
            message: "Verbindung zum Server fehlgeschlagen. Bitte überprüfe deine Internetverbindung."
        ) {
            print("Retry tapped")
        }

        OBSErrorCardView(
            message: "Unbekannter Fehler aufgetreten."
        )
    }
    .padding()
}

#Preview("Warning Card") {
    OBSWarningCardView(
        title: "Portal nicht konfiguriert",
        message: "Richte das Portal ein, um Fahrten hochzuladen.",
        actionTitle: "Einstellungen öffnen"
    ) {
        print("Settings tapped")
    }
    .padding()
}
