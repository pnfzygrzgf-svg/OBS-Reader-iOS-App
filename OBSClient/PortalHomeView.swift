// PortalHomeView.swift

import SwiftUI

/// Einstiegsseite für den Tab „Aufzeichnungen“.
/// Diese View zeigt eine einfache Übersichts-/Startseite mit drei Navigationskacheln.
///
/// Navigation zu:
/// 1) Fahrtaufzeichnungen & Upload
/// 2) Meine Portal-Tracks
/// 3) Portal-Einstellungen (Portal-URL, API-Key, Login-Hilfe)
struct PortalHomeView: View {

    var body: some View {
        // ZStack, damit wir einen Hintergrund unter den Scroll-Inhalt legen können
        ZStack {
            // Hintergrundfarbe passend zu iOS "Grouped" Tabellen/Listen
            Color(.systemGroupedBackground)
                .ignoresSafeArea() // Hintergrund soll auch unter Safe Areas (Notch/Home Indicator) gehen

            // ScrollView, damit der Inhalt auch auf kleinen Geräten nicht abgeschnitten wird
            ScrollView {
                VStack(spacing: 24) {
                    // Ausgelagerte Section (computed property) für bessere Lesbarkeit
                    navigationSection
                }
                // Außenabstände der gesamten Inhalte
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            // Optional: Scroll-Indikatoren ausblenden für "cleaner" UI
            .scrollIndicators(.hidden)
        }
        // Titel in der NavigationBar (setzt voraus, dass die View in einem NavigationStack steckt)
        .navigationTitle("OBS-Portal")
    }

    /// Enthält die drei Navigationskacheln.
    ///
    /// Wieso als computed property?
    /// - Trennt Layout in logischere Bausteine
    /// - `body` bleibt kurz und übersichtlich
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            // 1) Fahrtaufzeichnungen & Upload
            //
            // NavigationLink: Beim Tippen wird DataExportView geöffnet.
            // Label: Eine "Kachel" mit Icon + Titel + Beschreibung.
            NavigationLink {
                DataExportView()
            } label: {
                HStack(spacing: 12) {
                    // Icon links
                    Image(systemName: "folder")
                        .font(.title3)

                    // Textblock rechts vom Icon
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fahrten ins OBS-Portal hochladen")
                            .font(.obsSectionTitle)
                        Text("Aufgezeichnete Fahrten verwalten und hochladen.")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }

                    // Spacer sorgt dafür, dass der Inhalt links bleibt
                    Spacer()
                }
                // Kachel soll die ganze verfügbare Breite einnehmen,
                // der Inhalt bleibt dabei linksbündig
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Plain: verhindert das standardmäßige Link-Styling (z.B. blau, Highlight)
            .buttonStyle(.plain)
            // Custom Card-Style aus deinem Projekt (z.B. Hintergrund, Padding, CornerRadius, Shadow)
            .obsCardStyle()

            // 2) Meine Portal-Tracks
            //
            // Öffnet PortalTracksListView (Liste der im Portal gespeicherten Fahrten)
            NavigationLink {
                PortalTracksListView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fahrten im OBS-Portal")
                            .font(.obsSectionTitle)
                        Text("Im Portal gespeicherte Fahrten ansehen und öffnen.")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .obsCardStyle()

            // 3) Portal-Einstellungen
            //
            // Öffnet PortalSettingsView (Portal-URL, API-Key, Login-Hinweise)
            NavigationLink {
                PortalSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Portal-Einstellungen")
                            .font(.obsSectionTitle)
                        Text("Portal-URL, API-Key und Login-Hinweise verwalten.")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .obsCardStyle()
        }
    }
}

#Preview {
    // Preview in NavigationStack, damit navigationTitle und NavigationLink korrekt dargestellt werden
    NavigationStack {
        PortalHomeView()
    }
}
