// SPDX-License-Identifier: GPL-3.0-or-later

// PortalConfigCard.swift

import SwiftUI

/// Konfigurationskarte für das OBS-Portal:
/// - Portal-URL + API-Key erfassen
/// - Werte werden erst nach Tippen auf „Speichern“ übernommen
/// - Beispiel-URL erscheint nur als Placeholder (sekundäre Farbe)
///
/// OPTIK-UPDATE:
/// - klarer Header mit Status-Chip (V2)
/// - ruhige Labels + bessere Field-Optik
/// - Save-Button als eindeutige Primary Action
///
/// TECH-FIX:
/// - nutzt V2-Komponenten, um Kollisionen/“ambiguous“ Fehler zu vermeiden:
///   - OBSSectionHeaderV2 statt OBSSectionHeader
///   - OBSStatusChipV2 statt OBSStatusChip
///   - obsCardStyleV2() statt obsCardStyle()
struct PortalConfigCardView: View {

    // Persistierte (gespeicherte) Werte
    @AppStorage("obsBaseUrl") private var savedBaseUrl: String = ""
    @AppStorage("obsApiKey")  private var savedApiKey: String = ""

    // Entwurfs-/Eingabewerte (werden erst mit "Speichern" übernommen)
    @State private var draftBaseUrl: String = ""
    @State private var draftApiKey: String = ""

    // Kleine UI-Rückmeldung nach dem Speichern
    @State private var showSavedHint: Bool = false

    // Beispiel-URL nur als Placeholder (prompt), NICHT als initialer Text
    private let exampleBaseUrl = "https://portal.openbikesensor.org/"

    /// „Konfiguriert“ bezieht sich bewusst auf den *gespeicherten* Zustand.
    private var isSavedConfigured: Bool {
        !savedBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !savedApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ob es ungespeicherte Änderungen gibt.
    private var hasUnsavedChanges: Bool {
        draftBaseUrl != savedBaseUrl || draftApiKey != savedApiKey
    }

    /// Grobe Validierung der Eingaben (für Button-Enablement).
    private var isDraftValid: Bool {
        let urlString = draftBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyString = draftApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !urlString.isEmpty, !keyString.isEmpty else { return false }
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host,
              !host.isEmpty
        else { return false }

        return true
    }

    /// Status-Chip Text/Style auf Basis des gespeicherten Zustands.
    private var statusChip: (text: String, style: OBSStatusChipV2.Style) {
        if isSavedConfigured { return ("Bereit", .success) }
        return ("Nicht eingerichtet", .warning)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Kopfzeile: zeigt Status des *gespeicherten* Zustands
            HStack(alignment: .top, spacing: 12) {
                OBSSectionHeaderV2(
                    "OBS-Portal",
                    subtitle: "Portal-URL und API-Key werden lokal gespeichert."
                )

                Spacer()

                OBSStatusChipV2(text: statusChip.text, style: statusChip.style)
            }

            // Hinweis, wenn der User etwas geändert hat, aber noch nicht gespeichert
            if hasUnsavedChanges {
                Text("Änderungen noch nicht gespeichert.")
                    .font(.obsCaption)
                    .foregroundStyle(.orange)
            }

            Divider()

            // Portal-URL Eingabe
            VStack(alignment: .leading, spacing: 8) {
                Text("Portal-URL")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $draftBaseUrl,
                        prompt: Text(exampleBaseUrl)
                            .foregroundStyle(.secondary)
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .font(.obsBody)

                    if !draftBaseUrl.isEmpty {
                        Button {
                            draftBaseUrl = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Portal-URL löschen")
                    }
                }
            }

            // API-Key Eingabe
            VStack(alignment: .leading, spacing: 8) {
                Text("API-Key")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    SecureField("API-Key eintragen", text: $draftApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.obsBody)

                    if !draftApiKey.isEmpty {
                        Button {
                            draftApiKey = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("API-Key löschen")
                    }
                }
            }

            // Validierungs-/Hilfetext
            if !isDraftValid {
                Text("Bitte eine gültige Portal-URL und einen API-Key eintragen.")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)
            }

            // Speichern-Button + Feedback
            HStack(spacing: 12) {
                Spacer()

                Button {
                    save()
                } label: {
                    Label("Speichern", systemImage: "square.and.arrow.down")
                        .font(.obsBody.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDraftValid || !hasUnsavedChanges)
            }

            if showSavedHint {
                Text("Gespeichert.")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .obsCardStyleV2()
        .onAppear {
            // Draft-Werte beim Erscheinen mit den gespeicherten Werten initialisieren
            draftBaseUrl = savedBaseUrl
            draftApiKey  = savedApiKey
        }
    }

    /// Übernimmt Draft → AppStorage (persistiert) und zeigt kurz ein Feedback.
    private func save() {
        savedBaseUrl = draftBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        savedApiKey  = draftApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        Haptics.shared.success()
        showSavedHint = true
        Task {
            try? await Task.sleep(for: .seconds(OBSTiming.hintHideDelay))
            await MainActor.run {
                showSavedHint = false
            }
        }
    }
}
