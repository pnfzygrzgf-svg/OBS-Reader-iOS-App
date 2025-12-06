import SwiftUI

struct InfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Intro
                VStack(alignment: .leading, spacing: 8) {
                    Text("Über diese App")
                        .font(.title2)
                        .bold()

                    Text("""
Diese App zeichnet Fahrten und Überholabstände auf, die mit einem \
OpenBikeSensor Lite aufgezeichnet wurden.
""")

                    Link("Mehr zum OpenBikeSensor Lite",
                         destination: URL(string: "https://www.openbikesensor.org/docs/lite/")!)
                        .font(.subheadline)
                }

                // MARK: Credits
                VStack(alignment: .leading, spacing: 8) {
                    Text("Danksagungen & verwendete Projekte")
                        .font(.headline)

                    Group {
                        Text("OpenBikeSensor")
                            .bold()
                        Link("https://github.com/openbikesensor",
                             destination: URL(string: "https://github.com/openbikesensor")!)
                        Text("""
In dieser App wird Code des OpenBikeSensor-Projekts verwendet. \
Die Originalsoftware wird unter der GNU Lesser General Public License (LGPL-3.0) veröffentlicht.
""")
                    }

                    Divider().padding(.vertical, 8)

                    Group {
                        Text("OpenBikeSensor-Logo")
                            .bold()
                        Link("https://github.com/turbo-distortion/OpenBikeSensor-Logo",
                             destination: URL(string: "https://github.com/turbo-distortion/OpenBikeSensor-Logo")!)
                        Text("""
Das in dieser App verwendete OpenBikeSensor-Logo wurde von Lukas Betzler als Beitrag \
zum OpenBikeSensor-Projekt erstellt. Das Logo steht unter der Creative-Commons-Lizenz \
CC BY-SA 4.0. Bei Weitergabe oder Anpassungen ist eine Namensnennung und das Teilen \
unter derselben Lizenz erforderlich.
""")
                    }

                    Divider().padding(.vertical, 8)

                    Group {
                        Text("SimRa Android App")
                            .bold()
                        Link("https://github.com/simra-project/simra-android",
                             destination: URL(string: "https://github.com/simra-project/simra-android")!)
                        Text("""
Teile des Quellcodes, insbesondere zur Fahrtenaufzeichnung, basieren auf Code aus der \
SimRa Android App. Diese steht unter der Apache License 2.0.
""")
                    }
                }

                // MARK: Lizenz
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lizenz dieser App")
                        .font(.headline)

                    Text("""
Diese App wird als Open-Source-Software bereitgestellt.
Die genaue Lizenz und alle Drittanbieter-Lizenzen findest du im Quellcode-Repository \
(Datei LICENSE bzw. THIRD_PARTY_LICENSES).

Bitte beachte, dass für die oben genannten Projekte weiterhin deren eigene Lizenzen gelten \
(LGPL-3.0, CC BY-SA 4.0, Apache-2.0).
""")
                }
            }
            .padding()
        }
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        InfoView()
    }
}
