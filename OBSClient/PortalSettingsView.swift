// PortalSettingsView.swift
import SwiftUI

/// Seite für Portal-Einstellungen:
/// - Portal-URL & API-Key konfigurieren
/// - Erklärung, wie der Login im Portal funktioniert
struct PortalSettingsView: View {

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // ✅ Konfigurationskarte (URL + API-Key + Speichern)
                    // Wichtig: hier wird die umbenannte View verwendet:
                    // PortalConfigCardView statt PortalConfigCard
                    PortalConfigCardView()

                    // ✅ Info-Karte zum Login
                    loginInfoCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Portal-Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Karte, die kurz erklärt, wie der Login im Portal funktioniert.
    private var loginInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Login im OBS-Portal")
                .font(.obsSectionTitle)

            Text("""
Um deine Fahrten aus dem OBS-Portal in dieser App zu sehen:

1. Stelle hier Portal-URL und API-Key ein und tippe auf „Speichern“.
2. Öffne im Tab „Aufzeichnungen“ den Bereich „Meine Portal-Tracks“.
3. Tippe dort oben rechts auf „Login“.

In der Login-Ansicht meldest du dich mit deinem Konto im OBS-Portal an. Danach kehrst du zur App zurück und deine Portal-Tracks werden geladen.
""")
            .font(.obsFootnote)
            .foregroundStyle(.secondary)
        }
        .obsCardStyle()
    }
}

#Preview {
    NavigationStack {
        PortalSettingsView()
    }
}
