// SPDX-License-Identifier: GPL-3.0-or-later

// InfoView.swift

import SwiftUI

/// Info-Screen der App.
struct InfoView: View {
    var body: some View {
        GroupedScrollScreenV2 {
            VStack(alignment: .leading, spacing: 24) {
                aboutAppCard
                creditsCard
                licenseCard
            }
            .font(.obsBody)
        }
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Cards

    private var aboutAppCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OBSSectionHeaderV2("Über diese App")

            Text("""
Diese App zeichnet deine Fahrten und Überholabstände mit einem OpenBikeSensor auf.
Sie hilft dabei, kritische Überholmanöver sichtbar zu machen und die Daten auszuwerten.
""")

            if let url = URL(string: "https://www.openbikesensor.org/device/") {
                Link("Mehr zum OpenBikeSensor", destination: url)
                    .font(.obsFootnote.weight(.semibold))
            } else {
                Text("Mehr zum OpenBikeSensor (Link ungültig)")
                    .font(.obsFootnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .obsCardStyleV2()
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            OBSSectionHeaderV2("Danksagungen & verwendete Projekte")

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenBikeSensor")
                    .font(.obsBody.weight(.semibold))

                if let url = URL(string: "https://github.com/openbikesensor") {
                    Link("GitHub-Organisation", destination: url)
                } else {
                    Text("GitHub-Organisation (Link ungültig)")
                        .foregroundStyle(.secondary)
                }

                Text("""
In dieser App wird Code aus dem OpenBikeSensor-Projekt verwendet. \
Die Originalsoftware wird unter der GNU Lesser General Public License (LGPL-3.0) veröffentlicht.
""")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenBikeSensor-Logo")
                    .font(.obsBody.weight(.semibold))

                if let url = URL(string: "https://github.com/turbo-distortion/OpenBikeSensor-Logo") {
                    Link("Repository des Logos", destination: url)
                } else {
                    Text("Repository des Logos (Link ungültig)")
                        .foregroundStyle(.secondary)
                }

                Text("""
Das in dieser App verwendete OpenBikeSensor-Logo wurde von Lukas Betzler \
als Beitrag zum OpenBikeSensor-Projekt erstellt. Das Logo steht unter der \
Creative-Commons-Lizenz CC BY-SA 4.0.
""")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("SimRa Android App")
                    .font(.obsBody.weight(.semibold))

                if let url = URL(string: "https://github.com/simra-project/simra-android") {
                    Link("Projekt auf GitHub", destination: url)
                } else {
                    Text("Projekt auf GitHub (Link ungültig)")
                        .foregroundStyle(.secondary)
                }

                Text("""
Teile des Quellcodes – insbesondere zur Fahrtenaufzeichnung – basieren auf Code aus der \
SimRa Android App. Diese steht unter der Apache License 2.0.
""")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
            }
        }
        .obsCardStyleV2()
    }

    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OBSSectionHeaderV2("Lizenz dieser App")

            Text("""
Diese App wird als Open-Source-Software bereitgestellt.
Die genaue Lizenz und alle Drittanbieter-Lizenzen findest du im Quellcode-Repository \
(in den Dateien LICENSE bzw. THIRD_PARTY_LICENSES).
""")
            .font(.obsFootnote)
            .foregroundStyle(.secondary)
        }
        .obsCardStyleV2()
    }
}

#Preview {
    NavigationStack {
        InfoView()
    }
}
