import SwiftUI

/// Gemeinsame Konfigurationskarte für OBS-Portal:
/// - Basis-URL
/// - API-Key
///
/// Nutzt @AppStorage("obsBaseUrl") und @AppStorage("obsApiKey"),
/// d.h. Änderungen sind überall gültig (DataExportView, PortalTracksListView, …).
struct PortalConfigCard: View {

    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""
    @AppStorage("obsApiKey")  private var obsApiKey: String = ""

    private var isConfigured: Bool {
        !obsBaseUrl.isEmpty && !obsApiKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: isConfigured
                      ? "checkmark.seal.fill"
                      : "exclamationmark.triangle.fill")
                    .foregroundStyle(isConfigured ? .green : .orange)

                Text("OBS-Portal")
                    .font(.obsScreenTitle)

                Spacer()
            }

            Text(isConfigured
                 ? "OBS-Portal ist bereit zum Hochladen."
                 : "OBS-Portal ist noch nicht vollständig eingerichtet.")
            .font(.obsCaption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Portal-URL")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)

                TextField("https://portal.openbikesensor.org/", text: $obsBaseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .font(.obsBody)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API-Key")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)

                SecureField("API-Key eintragen", text: $obsApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.obsBody)
            }

            if !isConfigured {
                Text("Bitte Portal-URL und API-Key eintragen, um Fahrtaufzeichnungen direkt ins OBS-Portal hochzuladen.")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .obsCardStyle()
    }
}

#Preview {
    ScrollView {
        PortalConfigCard()
            .padding()
    }
}
