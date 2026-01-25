// PortalHomeView.swift

import SwiftUI

/// Einstiegsseite für den Tab „Aufzeichnungen".
/// Diese View zeigt eine einfache Übersichts-/Startseite mit Navigationskacheln.
///
/// Navigation zu:
/// 1) Lokale Fahrten (bewerten + ins Portal hochladen)
/// 2) Meine Portal-Tracks
/// 3) Portal-Einstellungen (Portal-URL, API-Key, Login-Hilfe)
///
/// OPTIK-UPDATE:
/// - echte „Kacheln“ (Row Cards) mit Chevron
/// - konsistente Section Header (V2)
/// - ruhiges Spacing + Inset-Grouped Hintergrund
///
/// TECH-FIX:
/// - nutzt V2-Komponenten, um Redeclaration/Ambiguous-Probleme zu vermeiden:
///   - OBSSectionHeaderV2 statt OBSSectionHeader
///   - OBSRowCardV2 statt OBSRowCard
struct PortalHomeView: View {

    var body: some View {
        ZStack {
            // Hintergrundfarbe passend zu iOS "Grouped" Tabellen/Listen
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            // ScrollView, damit der Inhalt auch auf kleinen Geräten nicht abgeschnitten wird
            ScrollView {
                VStack(spacing: 24) {
                    // Ausgelagerte Section (computed property) für bessere Lesbarkeit
                    navigationSection
                }
                // Außenabstände der gesamten Inhalte
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            // Optional: Scroll-Indikatoren ausblenden für "cleaner" UI
            .scrollIndicators(.hidden)
        }
        // Titel in der NavigationBar (setzt voraus, dass die View in einem NavigationStack steckt)
        .navigationTitle("OBS-Portal")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Enthält die drei Navigationskacheln.
    ///
    /// Wieso als computed property?
    /// - Trennt Layout in logischere Bausteine
    /// - `body` bleibt kurz und übersichtlich
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            OBSSectionHeaderV2(
                "Aufzeichnungen",
                subtitle: "Fahrten verwalten, bewerten und ins Portal hochladen."
            )

            // 1) Lokale Fahrten
            NavigationLink {
                LocalRidesListView()
            } label: {
                OBSRowCardV2(
                    icon: "bicycle",
                    title: "Lokale Fahrten",
                    subtitle: "Fahrten ansehen, bewerten und ins Portal hochladen."
                )
            }
            .buttonStyle(.plain)
            .obsCardStyleV2()

            // 2) Meine Portal-Tracks
            NavigationLink {
                PortalTracksListView()
            } label: {
                OBSRowCardV2(
                    icon: "list.bullet.rectangle",
                    title: "Fahrten im OBS-Portal",
                    subtitle: "Im Portal gespeicherte Fahrten ansehen und öffnen."
                )
            }
            .buttonStyle(.plain)
            .obsCardStyleV2()

            // 3) Portal-Einstellungen
            NavigationLink {
                PortalSettingsView()
            } label: {
                OBSRowCardV2(
                    icon: "gearshape",
                    title: "Portal-Einstellungen",
                    subtitle: "Portal-URL, API-Key und Login-Hinweise verwalten."
                )
            }
            .buttonStyle(.plain)
            .obsCardStyleV2()
        }
    }
}

#Preview {
    // Preview in NavigationStack, damit navigationTitle und NavigationLink korrekt dargestellt werden
    NavigationStack {
        PortalHomeView()
    }
}
