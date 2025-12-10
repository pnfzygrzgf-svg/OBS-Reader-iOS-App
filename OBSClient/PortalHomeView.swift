// PortalHomeView.swift

import SwiftUI

/// Einstiegsseite für den „Portal“-Tab.
/// - Portal-URL & API-Key konfigurieren
/// - Erklärt, wie der Login funktioniert
/// - Navigation zu:
///   - Fahrtaufzeichnungen & Upload
///   - Portal-Tracks (online)
///   - OpenBikeSensor-Portal (im Browser)
struct PortalHomeView: View {

    /// Portal-URL aus der zentralen Konfiguration.
    /// HINWEIS: Der Key ("portalBaseUrl") muss zur PortalConfigCard passen!
    @AppStorage("portalBaseUrl") private var portalBaseUrl: String = "https://portal.openbikesensor.org"

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Zentrale Portal-Konfiguration (einzige Stelle!)
                    PortalConfigCard()

                    loginInfoCard

                    navigationSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Portal")
    }

    /// Karte, die kurz erklärt, wie der Login im Portal funktioniert.
    /// Wichtig, weil der eigentliche Login-Button in der Portal-Tracks-Ansicht sitzt.
    private var loginInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Login im OBS-Portal")
                .font(.obsSectionTitle)

            Text("""
Um deine Fahrten aus dem OBS-Portal in dieser App zu sehen:

1. Stelle oben Portal-URL und API-Key ein.
2. Öffne unten „Meine Portal-Tracks“.
3. Tippe dort oben rechts auf „Login“.

In der Login-Ansicht meldest du dich mit deinem Konto im OBS-Portal an. Danach kehrst du zur App zurück und deine Portal-Tracks werden geladen.
""")
            .font(.obsFootnote)
            .foregroundStyle(.secondary)
        }
        .obsCardStyle()
    }

    /// Navigation zu den Bereichen:
    /// - Fahrtaufzeichnungen & Upload
    /// - Meine Portal-Tracks
    /// - OpenBikeSensor-Portal (im Browser öffnen)
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bereiche")
                .font(.obsScreenTitle)

            // 1. Fahrtaufzeichnungen & Upload (zuerst)
            NavigationLink {
                DataExportView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fahrtaufzeichnungen & Upload")
                            .font(.obsSectionTitle)
                        Text("Fahrtaufzeichnungen verwalten und ins Portal hochladen.")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .obsCardStyle()

            // 2. Meine Portal-Tracks
            NavigationLink {
                PortalTracksListView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meine Portal-Tracks")
                            .font(.obsSectionTitle)
                        Text("Fahrten ansehen, die im OBS-Portal gespeichert sind.")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .obsCardStyle()

            // 3. OpenBikeSensor-Portal (öffnet das Portal im Browser)
            Button {
                if let url = portalMapURL {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe.europe.africa")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenBikeSensor-Portal")
                            .font(.obsSectionTitle)
                        Text("Portal im Browser öffnen.")
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

    /// Baut die /map-URL des konfigurierten Portals.
    private var portalMapURL: URL? {
        let trimmed = portalBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cleanedBase: String
        if trimmed.hasSuffix("/") {
            cleanedBase = String(trimmed.dropLast())
        } else {
            cleanedBase = trimmed
        }

        return URL(string: "\(cleanedBase)/map")
    }
}

#Preview {
    NavigationStack {
        PortalHomeView()
    }
}
