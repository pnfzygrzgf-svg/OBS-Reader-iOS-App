// PortalSettingsView.swift

import SwiftUI

/// Seite für Portal-Einstellungen:
/// - Portal-URL & API-Key konfigurieren
/// - Erklärung, wie der Login im Portal funktioniert
///
/// OPTIK-UPDATE:
/// - konsistente Inset-Grouped Cards
/// - klare Section Header + ruhigere Typo
///
/// TECH-FIX:
/// - nutzt V2-Komponenten, um „Ambiguous use of init(_:subtitle:)“ zu vermeiden:
///   - OBSSectionHeaderV2 statt OBSSectionHeader
struct PortalSettingsView: View {

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // ✅ Konfigurationskarte (URL + API-Key + Speichern)
                    // Wichtig: PortalConfigCardView muss ebenfalls die V2-Header/Chips nutzen.
                    PortalConfigCardView()

                    // ✅ Info-Karte zum Login
                    loginInfoCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Portal-Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Karte, die kurz erklärt, wie der Login im Portal funktioniert.
    private var loginInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            OBSSectionHeaderV2("Login im OBS-Portal")

            Text("""
Um deine Fahrten aus dem OBS-Portal in dieser App zu sehen:

1. Stelle hier Portal-URL und API-Key ein und tippe auf „Speichern“.
2. Öffne im Tab „Aufzeichnungen“ den Bereich „Fahrten im OBS-Portal“.
3. Tippe dort oben rechts auf „Login“.

In der Login-Ansicht meldest du dich mit deinem Konto im OBS-Portal an. Danach kehrst du zur App zurück und deine Portal-Tracks werden geladen.
""")
            .font(.obsFootnote)
            .foregroundStyle(.secondary)
        }
        .obsCardStyleV2()
    }
}

#Preview {
    NavigationStack {
        PortalSettingsView()
    }
}
