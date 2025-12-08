import SwiftUI

struct InfoView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    aboutAppCard
                    creditsCard
                    licenseCard

                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .font(.obsBody) // Basis-Font in InfoView
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Cards

    private var aboutAppCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Über diese App")
                .font(.obsScreenTitle)

            Text("""
Diese App zeichnet deine Fahrten und Überholabstände mit einem OpenBikeSensor Lite auf.
Sie hilft dabei, kritische Überholmanöver sichtbar zu machen und die Daten auszuwerten.
""")

            Link("Mehr zum OpenBikeSensor Lite",
                 destination: URL(string: "https://www.openbikesensor.org/docs/lite/")!)
                .font(.obsFootnote.weight(.semibold))
        }
        .obsCardStyle()
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Danksagungen & verwendete Projekte")
                .font(.obsScreenTitle)

            // OpenBikeSensor
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

            // OpenBikeSensor-Logo
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

            // SimRa Android App
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
