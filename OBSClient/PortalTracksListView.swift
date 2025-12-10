import SwiftUI

struct PortalTracksListView: View {

    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""

    @State private var tracks: [PortalTrackSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    tracksSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
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
                Text("Keine Portal-URL gesetzt.\nBitte im Portal-Bereich konfigurieren.")
                    .multilineTextAlignment(.center)
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

    // MARK: - UI

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                

                Spacer()

                Button {
                    Task { await load() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Neu laden")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || obsBaseUrl.isEmpty)
            }

            if obsBaseUrl.isEmpty {
                noBaseUrlCard
                    .obsCardStyle()
            } else if isLoading && tracks.isEmpty {
                loadingCard
                    .obsCardStyle()
            } else if tracks.isEmpty {
                emptyTracksCard
                    .obsCardStyle()
            } else {
                // kleiner Hinweis zum Login (hier nochmal kurz)
                loginHintInline
                    .obsCardStyle()

                VStack(spacing: 12) {
                    if isLoading {
                        loadingInlineRow
                    }

                    ForEach(tracks) { track in
                        trackCard(for: track)
                            .obsCardStyle()
                    }
                }
            }
        }
    }

    private var noBaseUrlCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Keine Portal-URL eingetragen")
                .font(.obsSectionTitle)

            Text("Bitte im Bereich „Portal“ die Portal-URL konfigurieren.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Lade Tracks…")
                .font(.obsBody)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyTracksCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Keine Tracks gefunden")
                .font(.obsSectionTitle)

            Text("Es wurden noch keine Fahrten im Portal gespeichert oder es gibt momentan keine eigenen Tracks.")
                .font(.obsFootnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Kurz-Hinweis, dass der Login über den Button oben rechts läuft
    private var loginHintInline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Login-Hinweis")
                    .font(.obsSectionTitle)
            }
            Text("Falls keine oder nur wenige Fahrten angezeigt werden, prüfe, ob du oben rechts über „Login“ im OBS-Portal angemeldet bist.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
    }

    private var loadingInlineRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Aktualisiere Liste…")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trackCard(for track: PortalTrackSummary) -> some View {
        NavigationLink {
            PortalTrackDetailView(baseUrl: obsBaseUrl, track: track)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(track.title?.isEmpty == false ? track.title! : "(ohne Titel)")
                    .font(.obsSectionTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("Portal-ID: \(track.slug)")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text(String(format: "Länge: %.2f km", track.length / 1000.0))
                    Text("Dauer: \(formattedDuration(track.duration))")
                    Text("Events: \(track.numEvents)")
                }
                .font(.obsCaption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }

    // MARK: - Laden der eigenen Tracks (Feed)

    private func load() async {
        guard !obsBaseUrl.isEmpty else {
            errorMessage = "Portal-URL ist leer. Bitte im Bereich „Portal“ eintragen."
            tracks = []
            return
        }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let client = PortalApiClient(baseUrl: obsBaseUrl)
            let result = try await client.fetchMyTracks(limit: 20)
            tracks = result.tracks
            errorMessage = nil

            print("PortalTracksListView: \(result.tracks.count) Tracks geladen")
        } catch let PortalApiError.httpError(status, body) where status == 401 {
            print("PortalTracksListView: 401 Unauthorized – Body: \(body)")
            errorMessage = "Nicht im Portal eingeloggt.\nBitte oben auf „Login“ tippen und dich anmelden."
            tracks = []
        } catch PortalApiError.invalidBaseUrl {
            errorMessage = """
            Portal-URL ist ungültig:

            \(obsBaseUrl)

            Bitte im Bereich „Portal“ inkl. https:// eintragen.
            """
            tracks = []
        } catch PortalApiError.invalidURL {
            errorMessage = "Interne URL konnte nicht gebaut werden.\nBitte Portal-URL prüfen."
            tracks = []
        } catch PortalApiError.noHTTPResponse {
            errorMessage = "Keine gültige HTTP-Antwort vom Portal erhalten.\nIst das Portal erreichbar?"
            tracks = []
        } catch let PortalApiError.httpError(status, body) {
            errorMessage = "Serverfehler \(status).\nAntwort:\n\(body)"
            tracks = []
        } catch {
            errorMessage = "Unbekannter Fehler: \(error.localizedDescription)"
            tracks = []
        }
    }
}

#Preview {
    NavigationStack {
        PortalTracksListView()
    }
}
