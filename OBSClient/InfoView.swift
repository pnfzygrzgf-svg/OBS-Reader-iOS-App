// InfoView.swift

import SwiftUI

/// Zeigt Hintergrundinformationen zur App:
/// - Kurzbeschreibung der App
/// - Danksagungen / verwendete Projekte
/// - Lizenzhinweise
///
/// Aufbau:
/// - ScrollView mit mehreren "Cards" (aboutAppCard, creditsCard, licenseCard)
/// - Konsistenter Look über `.obsCardStyle()` und `.obsBody`-Font
struct InfoView: View {
    var body: some View {
        ZStack {
            // System-Hintergrundfarbe (wie in Einstellungen-App)
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Inhaltliche Abschnitte als eigene "Cards"
                    aboutAppCard
                    creditsCard
                    licenseCard

                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
                // Basis-Font in InfoView; einzelne Texte können davon abweichen
                .font(.obsBody)
            }
            .scrollIndicators(.hidden)
        }
        // Titel in der Navigationsleiste
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Cards

    /// Karte mit einer kurzen Beschreibung der App und Link zur OBS-Lite-Doku.
    private var aboutAppCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Über diese App")
                .font(.obsScreenTitle)

            Text("""
Diese App zeichnet deine Fahrten und Überholabstände mit einem OpenBikeSensor auf.
Sie hilft dabei, kritische Überholmanöver sichtbar zu machen und die Daten auszuwerten.
""")

            // Externer Link zur Dokumentation des OpenBikeSensor Lite
            Link("Mehr zum OpenBikeSensor",
                 destination: URL(string: "https://www.openbikesensor.org/device/")!)
                .font(.obsFootnote.weight(.semibold))
        }
        // Einheitlicher Card-Look (vermutlich: Hintergrund, CornerRadius, Shadow, etc.)
        .obsCardStyle()
    }

    /// Karte mit Danksagungen und Referenzen auf verwendete Open-Source-Projekte.
    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Danksagungen & verwendete Projekte")
                .font(.obsScreenTitle)

            // MARK: OpenBikeSensor
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenBikeSensor")
                    .font(.obsBody.weight(.bold))

                Link("Github-Organisation",
                     destination: URL(string: "https://github.com/openbikesensor")!)

                Text("""
In dieser App wird Code aus dem OpenBikeSensor-Projekt verwendet. \
Die Originalsoftware wird unter der GNU Lesser General Public License (LGPL-3.0) veröffentlicht.
""")
            }

            Divider().padding(.vertical, 4)

            // MARK: OpenBikeSensor-Logo
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenBikeSensor-Logo")
                    .font(.obsBody.weight(.bold))

                Link("Repository des Logos",
                     destination: URL(string: "https://github.com/turbo-distortion/OpenBikeSensor-Logo")!)

                Text("""
Das in dieser App verwendete OpenBikeSensor-Logo wurde von Lukas Betzler \
als Beitrag zum OpenBikeSensor-Projekt erstellt. Das Logo steht unter der \
Creative-Commons-Lizenz CC BY-SA 4.0. Bei Weitergabe oder Anpassungen sind \
eine Namensnennung und das Teilen unter derselben Lizenz erforderlich.
""")
            }

            Divider().padding(.vertical, 4)

            // MARK: SimRa Android App
            VStack(alignment: .leading, spacing: 8) {
                Text("SimRa Android App")
                    .font(.obsBody.weight(.bold))

                Link("Projekt auf GitHub",
                     destination: URL(string: "https://github.com/simra-project/simra-android")!)

                Text("""
Teile des Quellcodes – insbesondere zur Fahrtenaufzeichnung – basieren auf Code aus der \
SimRa Android App. Diese steht unter der Apache License 2.0.
""")
            }
        }
        .obsCardStyle()
    }

    /// Karte mit Lizenzhinweisen für diese App und Hinweis auf Drittanbieter-Lizenzen.
    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lizenz dieser App")
                .font(.obsScreenTitle)

            Text("""
Diese App wird als Open-Source-Software bereitgestellt.
Die genaue Lizenz und alle Drittanbieter-Lizenzen findest du im Quellcode-Repository \
(in den Dateien LICENSE bzw. THIRD_PARTY_LICENSES).

Bitte beachte, dass für die oben genannten Projekte weiterhin deren eigenen \
Lizenzen gelten (LGPL-3.0, CC BY-SA 4.0, Apache-2.0).
""")
        }
        .obsCardStyle()
    }
}

#Preview {
    NavigationStack {
        InfoView()
    }
}
