import SwiftUI

struct PortalTracksRawView: View {

    // gleiche Key wie in deiner DataExportView (falls dort schon benutzt),
    // ansonsten ist das einfach eine persistent gespeicherte URL.
    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""

    @State private var isLoading = false
    @State private var message: String = "Noch nichts geladen."

    var body: some View {
        VStack(spacing: 16) {
            Text("Portal-API-Raw-Test")
                .font(.title2)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Portal-URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("https://portal.openbikesensor.org", text: $obsBaseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            Button {
                Task {
                    await load()
                }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("API-Test starten")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(obsBaseUrl.isEmpty || isLoading)

            Divider()
                .padding(.vertical, 8)

            Text("Hinweis")
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
        .navigationTitle("Portal-API Test")
    }

    private func load() async {
        guard !obsBaseUrl.isEmpty else {
            message = "Keine Basis-URL gesetzt."
            return
        }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        message = "Request läuft… schau in die Xcode-Konsole."

        await portalApiPrintTracks(baseUrl: obsBaseUrl)

        message = "Request fertig. Ausgabe steht in der Xcode-Konsole."
    }
}

#Preview {
    NavigationStack {
        PortalTracksRawView()
    }
}
