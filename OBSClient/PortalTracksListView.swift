import SwiftUI

struct PortalTracksListView: View {

    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""

    @State private var tracks: [PortalTrackSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    var body: some View {
        VStack(spacing: 16) {
            // Konfig-Bereich für die Portal-URL
            VStack(alignment: .leading, spacing: 8) {
                Text("Portal-URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("https://portal.openbikesensor.org", text: $obsBaseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                Button("Neu laden") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(obsBaseUrl.isEmpty || isLoading)
            }
            .padding(.horizontal)

            // Liste der Tracks oder Hinweis
            Group {
                if obsBaseUrl.isEmpty {
                    VStack(spacing: 12) {
                        Text("Keine Portal-URL eingetragen")
                            .font(.headline)
                        Text("Trage oben z.B. ein:\nhttps://portal.openbikesensor.org")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        if isLoading {
                            ProgressView("Lade Tracks…")
                        }

                        ForEach(tracks) { track in
                            NavigationLink {
                                // Ziel: Detail-Ansicht
                                PortalTrackDetailView(baseUrl: obsBaseUrl, track: track)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text((track.title?.isEmpty == false ? track.title! : "(ohne Titel)"))
                                        .font(.headline)
                                        .lineLimit(1)

                                    Text("Slug: \(track.slug)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    HStack(spacing: 12) {
                                        Text(String(format: "Länge: %.2f km", track.length / 1000.0))
                                        Text("Events: \(track.numEvents)")
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                }
            }
        }
        .navigationTitle("Portal-Tracks")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Login") {
                    showingLogin = true
                }
                .disabled(obsBaseUrl.isEmpty)
            }
        }
        .task {
            await load()
        }
        .sheet(isPresented: $showingLogin) {
            if !obsBaseUrl.isEmpty {
                PortalLoginView(baseUrl: obsBaseUrl) {
                    Task { await load() }
                }
            } else {
                Text("Keine Portal-URL gesetzt.")
                    .padding()
            }
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Laden der eigenen Tracks (Feed)

    private func load() async {
        guard !obsBaseUrl.isEmpty else {
            errorMessage = "Portal-URL ist leer. Bitte z.B. https://portal.openbikesensor.org eintragen."
            tracks = []
            return
        }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let client = PortalApiClient(baseUrl: obsBaseUrl)

            // Eigene Fahrten (Feed):
            let result = try await client.fetchMyTracks(limit: 20)
            tracks = result.tracks
            errorMessage = nil

            print("PortalTracksListView: \(result.tracks.count) Tracks geladen")
        } catch let PortalApiError.httpError(status, body) where status == 401 {
            print("PortalTracksListView: 401 Unauthorized – Body: \(body)")
            errorMessage = "Nicht im Portal eingeloggt.\nBitte oben auf „Login“ tippen und dich anmelden."
            tracks = []
        } catch PortalApiError.invalidBaseUrl {
            print("PortalTracksListView: invalidBaseUrl – obsBaseUrl = \(obsBaseUrl)")
            errorMessage = """
            Portal-URL ist ungültig:

            \(obsBaseUrl)

            Bitte inkl. https:// eintragen, z.B.
            https://portal.openbikesensor.org
            """
            tracks = []
        } catch PortalApiError.invalidURL {
            print("PortalTracksListView: invalidURL – obsBaseUrl = \(obsBaseUrl)")
            errorMessage = "Interne URL konnte nicht gebaut werden.\nBitte Portal-URL prüfen."
            tracks = []
        } catch PortalApiError.noHTTPResponse {
            print("PortalTracksListView: noHTTPResponse")
            errorMessage = "Keine gültige HTTP-Antwort vom Portal erhalten.\nIst das Portal erreichbar?"
            tracks = []
        } catch let PortalApiError.httpError(status, body) {
            print("PortalTracksListView: httpError \(status) – Body: \(body)")
            errorMessage = "Serverfehler \(status).\nAntwort:\n\(body)"
            tracks = []
        } catch {
            print("PortalTracksListView: unbekannter Fehler: \(error)")
            errorMessage = "Unbekannter Fehler: \(error.localizedDescription)"
            tracks = []
        }
    }
}

#Preview {
    NavigationView {
        PortalTracksListView()
    }
}
