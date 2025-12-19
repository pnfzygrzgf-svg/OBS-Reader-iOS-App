// PortalTracksListView.swift
import SwiftUI

/// Liste „Meine Portal-Tracks“
///
/// Aufgaben dieser View:
/// - Lädt die eigenen Tracks aus dem OBS-Portal (API)
/// - Sortiert nach Fahrtdatum (neueste zuerst)
/// - Zeigt Zustände an: keine Portal-URL / lädt / leer / Liste
/// - Bietet „Login“-Button (öffnet WebView-Login)
struct PortalTracksListView: View {

    // Portal-URL wird aus AppStorage gelesen (zentral konfiguriert in PortalConfigCard)
    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""

    // Geladene Tracks (Kurzfassung/Summary)
    @State private var tracks: [PortalTrackSummary] = []

    // Lade- und Fehlerzustände
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Steuert das Sheet für die Login-WebView
    @State private var showingLogin = false

    var body: some View {
        // Gruppierter Screen-Hintergrund (Custom Container in deinem Projekt)
        GroupedScrollScreen {
            VStack(spacing: 24) {

                // Kurze Einleitung oberhalb der Liste
                VStack(alignment: .leading, spacing: 6) {
                    Text("Im Portal gespeicherte Fahrten ansehen. Sortiert nach Fahrtdatum (neueste zuerst).")
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true) // Text darf umbrechen
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Bereich mit Reload-Button + Karten/Liste
                tracksSection
            }
        }
        .navigationTitle("Fahrten im OBS-Portal")

        // Toolbar: Login-Button oben rechts
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Login nur möglich, wenn eine Portal-URL vorhanden ist
                Button("Login") { showingLogin = true }
                    .disabled(obsBaseUrl.isEmpty)
            }
        }

        // Beim Erscheinen automatisch laden
        .task { await load() }

        // Login-Sheet: zeigt PortalLoginView oder Hinweis wenn keine URL gesetzt ist
        .sheet(isPresented: $showingLogin) {
            if !obsBaseUrl.isEmpty {
                // Nach „Fertig“ im Login: Cookies sync + dann hier erneut laden
                PortalLoginView(baseUrl: obsBaseUrl) {
                    Task { await load() }
                }
            } else {
                // Fallback: falls obsBaseUrl leer ist, obwohl Login-Sheet geöffnet wurde
                Text("Keine Portal-URL gesetzt.\nBitte in den Portal-Einstellungen konfigurieren.")
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }

        // Fehler-Alert (sichtbar, wenn errorMessage != nil)
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } } // beim Schließen zurücksetzen
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - UI

    /// Hauptbereich unterhalb der Einleitung:
    /// - Reload-Button
    /// - Zustandskarten (keine URL / lädt / leer)
    /// - oder Liste der Tracks
    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Oben rechts: „Neu laden“-Button
            HStack {
                Spacer()
                Button {
                    // Async-Ladevorgang erneut starten
                    Task { await load() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Neu laden")
                    }
                }
                .buttonStyle(.bordered)

                // Disabled, wenn gerade geladen wird oder keine Portal-URL gesetzt ist
                .disabled(isLoading || obsBaseUrl.isEmpty)
            }

            // Zustände der UI:
            // 1) keine Portal-URL → Hinweis anzeigen
            // 2) lädt und noch keine Daten → Ladekarte anzeigen
            // 3) fertig, aber leer → Leerzustand anzeigen
            // 4) Daten vorhanden → Login-Hinweis + Liste
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
                // Hinweis: ggf. im Portal einloggen, wenn wenig angezeigt wird
                loginHintInline
                    .obsCardStyle()

                // Track-Liste als „Cards“
                VStack(spacing: 12) {

                    // Wenn währenddessen neu geladen wird, kurze Inline-Progresszeile
                    if isLoading {
                        loadingInlineRow
                    }

                    // Für jeden Track eine tappbare Karte (NavigationLink zum Detail)
                    ForEach(tracks) { track in
                        trackCard(for: track)
                            .obsCardStyle()
                    }
                }
            }
        }
    }

    /// Karte: Portal-URL fehlt
    private var noBaseUrlCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Keine Portal-URL eingetragen")
                .font(.obsSectionTitle)

            Text("Bitte in den Portal-Einstellungen die Portal-URL konfigurieren.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Karte: Initialer Ladezustand (wenn Liste noch leer ist)
    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Lade Tracks…")
                .font(.obsBody)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Karte: keine Tracks vorhanden
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

    /// Inline-Hinweis, dass ggf. ein Login nötig ist
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

    /// Kleine Ladezeile für „Reload während schon Daten da sind“
    private var loadingInlineRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Aktualisiere Liste…")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Einzelne Track-Karte, tappbar → navigiert zur Detail-View
    private func trackCard(for track: PortalTrackSummary) -> some View {
        // Titel: optional/leer → Fallback
        let title = track.title.obsDisplayText(or: "(ohne Titel)")

        return NavigationLink {
            // Detailansicht: baseUrl wird weitergereicht, damit dort API-Calls möglich sind
            PortalTrackDetailView(baseUrl: obsBaseUrl, track: track)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.obsSectionTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Track-ID im Portal
                Text("Portal-ID: \(track.slug)")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)

                // Kennzahlen (monospacedDigit für stabilere Zahlendarstellung)
                HStack(spacing: 12) {
                    Text(String(format: "Länge: %.2f km", track.length / 1000.0))
                    Text("Dauer: \(DurationText.format(track.duration))")
                    Text("Events: \(track.numEvents)")
                }
                .font(.obsCaption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain) // entfernt Standard-Link-Optik
    }

    // MARK: - Datum Parsing (Portal-Format)

    /// Hilfs-Typ zum Parsen der Portal-Datumsstrings.
    /// Hintergrund: Das Portal liefert teils Strings mit und teils ohne Bruchteile von Sekunden.
    private enum PortalDate {

        /// Format mit Fractional Seconds (z.B. ...:12.123456+0000)
        private static let dfWithFraction: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX") // robustes Parsing unabhängig von Locale
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
            return df
        }()

        /// Format ohne Fractional Seconds (z.B. ...:12+0000)
        private static let dfNoFraction: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            return df
        }()

        /// Versucht beide Formate; wenn nichts passt, fällt es auf distantPast zurück
        /// (damit Sortierung nicht crasht, aber die „unparsbaren“ weit hinten landen)
        static func parse(_ s: String) -> Date {
            if let d = dfWithFraction.date(from: s) { return d }
            if let d = dfNoFraction.date(from: s) { return d }
            return .distantPast
        }
    }

    // MARK: - Laden

    /// Lädt die eigenen Tracks aus dem Portal.
    /// - Bei 401: zeigt Hinweis, dass Login nötig ist.
    /// - Bei ungültiger URL: zeigt Config-Hinweis.
    private func load() async {
        // Ohne Portal-URL macht der API Call keinen Sinn
        guard !obsBaseUrl.isEmpty else {
            errorMessage = "Portal-URL ist leer. Bitte in den Portal-Einstellungen eintragen."
            tracks = []
            return
        }

        // Doppelte Requests verhindern
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false } // sorgt dafür, dass isLoading am Ende sicher zurückgesetzt wird

        do {
            // API Client erstellen und Tracks abrufen
            let client = PortalApiClient(baseUrl: obsBaseUrl)
            let result = try await client.fetchMyTracks(limit: 20)

            // Sortieren: neueste Aufnahme zuerst (recordedAt absteigend)
            tracks = result.tracks.sorted {
                PortalDate.parse($0.recordedAt) > PortalDate.parse($1.recordedAt)
            }

            errorMessage = nil
            print("PortalTracksListView: \(result.tracks.count) Tracks geladen")

        } catch let PortalApiError.httpError(status, body) where status == 401 {
            // 401 = nicht eingeloggt / keine Berechtigung
            print("PortalTracksListView: 401 Unauthorized – Body: \(body)")
            errorMessage = "Nicht im Portal eingeloggt.\nBitte oben auf „Login“ tippen und dich anmelden."
            tracks = []

        } catch PortalApiError.invalidBaseUrl {
            // baseUrl im AppStorage ist syntaktisch ungültig
            errorMessage = """
            Portal-URL ist ungültig:

            \(obsBaseUrl)

            Bitte in den Portal-Einstellungen inkl. https:// eintragen.
            """
            tracks = []

        } catch PortalApiError.invalidURL {
            // Interner Fehler beim Bauen eines Endpunkt-URLs
            errorMessage = "Interne URL konnte nicht gebaut werden.\nBitte Portal-URL prüfen."
            tracks = []

        } catch PortalApiError.noHTTPResponse {
            // Netzwerkproblem / Server nicht erreichbar / keine Antwort
            errorMessage = "Keine gültige HTTP-Antwort vom Portal erhalten.\nIst das Portal erreichbar?"
            tracks = []

        } catch let PortalApiError.httpError(status, body) {
            // Allgemeiner HTTP-Fehler
            errorMessage = "Serverfehler \(status).\nAntwort:\n\(body)"
            tracks = []

        } catch {
            // Unbekannter Fehler (Decoding, Netzwerk, etc.)
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
