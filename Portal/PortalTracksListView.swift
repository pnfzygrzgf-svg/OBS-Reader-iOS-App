// SPDX-License-Identifier: GPL-3.0-or-later

// PortalTracksListView.swift

import SwiftUI

struct PortalTracksListView: View {

    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""

    @State private var tracks: [PortalTrackSummary] = []

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    // 1) Tracks, die beim Decoding übersprungen wurden (wirklich kaputtes JSON)
    @State private var skippedTracksCount: Int = 0

    // 2) Tracks, die zwar decodierbar sind, aber im Portal als „fehlerhaft“ gelten (Status)
    @State private var faultyTracksCount: Int = 0

    var body: some View {
        List {

            Section {
                Text("Im Portal gespeicherte Fahrten ansehen. Sortiert nach Fahrtdatum (neueste zuerst).")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
            }

            Section {
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

                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            if obsBaseUrl.isEmpty {
                noBaseUrlCard
                    .listRowSeparator(.hidden)

            } else if isLoading && tracks.isEmpty {
                loadingCard
                    .listRowSeparator(.hidden)

            } else if tracks.isEmpty {
                // ✅ Warnung auch dann zeigen, wenn alles leer ist, aber es Skips/Fehler gab
                if skippedTracksCount > 0 || faultyTracksCount > 0 {
                    portalIssuesCard
                        .listRowSeparator(.hidden)
                }

                emptyTracksCard
                    .listRowSeparator(.hidden)

            } else {
                // ✅ Warnung oben
                if skippedTracksCount > 0 || faultyTracksCount > 0 {
                    portalIssuesCard
                        .listRowSeparator(.hidden)
                }

                loginHintInline
                    .listRowSeparator(.hidden)

                if isLoading {
                    loadingInlineRow
                        .listRowSeparator(.hidden)
                }

                ForEach(tracks) { track in
                    NavigationLink {
                        PortalTrackDetailView(baseUrl: obsBaseUrl, track: track)
                    } label: {
                        PortalTrackRowContent(track: track)
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            Haptics.shared.light()
            await load()
        }
        .navigationTitle("Fahrten im OBS-Portal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Login") { showingLogin = true }
                    .disabled(obsBaseUrl.isEmpty)
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingLogin) {
            if !obsBaseUrl.isEmpty {
                PortalLoginView(baseUrl: obsBaseUrl) {
                    Task { await load() }
                }
            } else {
                Text("Keine Portal-URL gesetzt.\nBitte in den Portal-Einstellungen konfigurieren.")
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
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Cards

    private var noBaseUrlCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            OBSSectionHeaderV2(
                "Keine Portal-URL eingetragen",
                subtitle: "Bitte in den Portal-Einstellungen konfigurieren."
            )

            Text("Ohne Portal-URL können keine Tracks geladen werden.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .obsCardStyleV2()
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Lade Tracks…")
                .font(.obsBody)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .obsCardStyleV2()
    }

    private var emptyTracksCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            OBSSectionHeaderV2(
                "Keine Tracks gefunden",
                subtitle: "Entweder sind keine Fahrten im Portal gespeichert oder du bist nicht eingeloggt."
            )

            Text("Wenn du sicher bist, dass Tracks existieren: Tippe oben auf „Login“ und lade danach neu.")
                .font(.obsFootnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .obsCardStyleV2()
    }

    /// ✅ Warn-Card für Portal-Probleme (Decoding-Skips + fehlerhafte Status)
    private var portalIssuesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Problem im Portal erkannt")
                        .font(.obsSectionTitle)

                    // Text je nach Ursache
                    if skippedTracksCount > 0 && faultyTracksCount > 0 {
                        Text("\(skippedTracksCount) Eintrag(e) konnten nicht gelesen werden + \(faultyTracksCount) Fahrt(en) sind im Portal fehlerhaft.")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    } else if skippedTracksCount > 0 {
                        Text("\(skippedTracksCount) Eintrag(e) konnten nicht gelesen und wurden übersprungen.")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(faultyTracksCount) Fahrt(en) sind im Portal fehlerhaft (rotes Warnsymbol).")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Bitte öffne das Portal, prüfe/lösche die betroffene(n) Fahrt(en) und lade danach neu.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .obsCardStyleV2()
    }

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
        .obsCardStyleV2()
    }

    private var loadingInlineRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Aktualisiere Liste…")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .obsCardStyleV2()
    }

    // MARK: - Datum Parsing

    private enum PortalDate {
        private static let dfWithFraction: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
            return df
        }()

        private static let dfNoFraction: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            return df
        }()

        static func parse(_ s: String) -> Date {
            if let d = dfWithFraction.date(from: s) { return d }
            if let d = dfNoFraction.date(from: s) { return d }
            return .distantPast
        }
    }

    // MARK: - Faulty Detection

    /// Heuristik: welche Status gelten als „OK“?
    private func isOkStatus(_ s: String) -> Bool {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty { return true } // manche Backends liefern leer -> nicht sofort als Fehler werten
        let ok: Set<String> = ["done", "complete", "completed", "finished", "success", "ok"]
        return ok.contains(v)
    }

    private func isFaultyTrack(_ t: PortalTrackSummary) -> Bool {
        // 1) Status sagt „nicht ok“
        if !isOkStatus(t.processingStatus) { return true }

        // 2) Optional zusätzliche Heuristik (falls Status nicht zuverlässig):
        //    z.B. Dauer 0 + Länge 0 deutet oft auf kaputte/fehlgeschlagene Verarbeitung hin.
        if t.duration <= 0 && t.length <= 0 { return true }

        return false
    }

    // MARK: - Load

    private func load() async {
        guard !obsBaseUrl.isEmpty else {
            errorMessage = "Portal-URL ist leer. Bitte in den Portal-Einstellungen eintragen."
            tracks = []
            skippedTracksCount = 0
            faultyTracksCount = 0
            return
        }

        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let client = PortalApiClient(baseUrl: obsBaseUrl)
            let result = try await client.fetchMyTracks(limit: 20)

            // ✅ 1) Skipped (nur bei wirklichem Decode-Fehler)
            skippedTracksCount = result.skippedTracksCount

            // ✅ 2) Faulty (Status/Heuristik)
            faultyTracksCount = result.tracks.filter { isFaultyTrack($0) }.count

            let sorted = result.tracks.sorted {
                PortalDate.parse($0.recordedAt) > PortalDate.parse($1.recordedAt)
            }

            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                tracks = sorted
            }

            errorMessage = nil

        } catch let PortalApiError.httpError(status, body) where status == 401 {
            errorMessage = "Nicht im Portal eingeloggt.\nBitte oben auf „Login“ tippen und dich anmelden.\n\nAntwort:\n\(body)"
            tracks = []
            skippedTracksCount = 0
            faultyTracksCount = 0

        } catch PortalApiError.invalidBaseUrl {
            errorMessage = """
            Portal-URL ist ungültig:

            \(obsBaseUrl)

            Bitte in den Portal-Einstellungen inkl. https:// eintragen.
            """
            tracks = []
            skippedTracksCount = 0
            faultyTracksCount = 0

        } catch PortalApiError.invalidURL {
            errorMessage = "Interne URL konnte nicht gebaut werden.\nBitte Portal-URL prüfen."
            tracks = []
            skippedTracksCount = 0
            faultyTracksCount = 0

        } catch PortalApiError.noHTTPResponse {
            errorMessage = "Keine gültige HTTP-Antwort vom Portal erhalten.\nIst das Portal erreichbar?"
            tracks = []
            skippedTracksCount = 0
            faultyTracksCount = 0

        } catch let PortalApiError.httpError(status, body) {
            errorMessage = "Serverfehler \(status).\nAntwort:\n\(body)"
            tracks = []
            skippedTracksCount = 0
            faultyTracksCount = 0

        } catch {
            errorMessage = "Unbekannter Fehler: \(error.localizedDescription)"
            tracks = []
            skippedTracksCount = 0
            faultyTracksCount = 0
        }
    }
}

// MARK: - Row Content

private struct PortalTrackRowContent: View {
    let track: PortalTrackSummary

    var body: some View {
        let title = (track.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? track.title!
            : "(ohne Titel)"

        VStack(alignment: .leading, spacing: 6) {
            Text(title)
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
        .padding(.vertical, 4)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
}

#Preview {
    NavigationStack {
        PortalTracksListView()
    }
}
