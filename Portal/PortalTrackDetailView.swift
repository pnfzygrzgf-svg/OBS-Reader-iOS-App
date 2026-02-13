// PortalTrackDetailView.swift

import SwiftUI
import CoreLocation

/// Detailansicht für einen Portal-Track.
/// Zeigt:
/// - Kopfkarte (Titel, Autor, Kennzahlen)
/// - Karte mit Route + Event-Markern (OvertakeEvents)
/// - Einklappbare Detail-Liste (DisclosureGroup)
///
/// OPTIK-UPDATE:
/// - GroupedScrollScreenV2 Wrapper statt eigenem ZStack/ScrollView
/// - Header: klare Hierarchie (Titel groß, Meta klein)
/// - Map: sauberer Card-Look + klarer Fullscreen Button
/// - Details: ruhigere Rows (Label links sekundär, Value rechts)
struct PortalTrackDetailView: View {

    // Basis-URL des Portals (wird für API-Calls genutzt)
    let baseUrl: String

    // Track, der beim Öffnen der View bereits bekannt ist (z.B. aus einer Liste)
    let initialTrack: PortalTrackSummary

    // Aktueller Track-Zustand in der View:
    // wird zuerst mit initialTrack befüllt und nach dem Nachladen durch Detaildaten ersetzt
    @State private var track: PortalTrackSummary

    // Lade-/Fehlerzustand für Detaildaten
    @State private var isLoading = false
    @State private var errorMessage: String?

    // MARK: - Karte / Map State

    // Route als Liste von Koordinaten (Polyline)
    @State private var mapRoute: [CLLocationCoordinate2D] = []

    // Events (z.B. Überholvorgänge) als Marker/Annotationen
    @State private var mapEvents: [OvertakeEvent] = []

    // Ladezustand speziell für Map-Daten (Route + Events)
    @State private var isLoadingMap = false

    // MARK: - UI State

    // Details ein-/ausklappbar – standardmäßig eingeklappt (false)
    @State private var showDetails = false

    // Fullscreen-State für die Karte (öffnet PortalTrackMapView in fullScreenCover)
    @State private var showFullscreenMap = false

    // MARK: - Delete State
    @AppStorage("obsApiKey") private var obsApiKey: String = ""
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss

    /// Custom init, weil `track` als @State initialisiert werden muss.
    /// - `initialTrack` bleibt unverändert als Referenz für slug/Startdaten
    /// - `track` ist der veränderliche State für die UI
    init(baseUrl: String, track: PortalTrackSummary) {
        self.baseUrl = baseUrl
        self.initialTrack = track
        _track = State(initialValue: track)
    }

    var body: some View {
        GroupedScrollScreenV2 {
            VStack(alignment: .leading, spacing: 16) {
                headerCard   // Titel/Autor/Kennzahlen
                mapCard      // Karte + Ladezustand + Fullscreen
                detailsCard  // DisclosureGroup mit Details
            }
        }
        .navigationTitle("Track-Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(obsApiKey.isEmpty || isDeleting)
            }
        }
        .task {
            await loadDetail()
            await loadTrackData()
        }
        .alert("Fahrt löschen?", isPresented: $showDeleteConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                Task { await deleteTrack() }
            }
        } message: {
            Text("Diese Fahrt wird unwiderruflich aus dem Portal gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.")
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
        .fullScreenCover(isPresented: $showFullscreenMap) {
            ZStack(alignment: .topTrailing) {
                PortalTrackMapView(route: mapRoute, events: mapEvents)
                    .ignoresSafeArea()

                Button {
                    showFullscreenMap = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }
                .padding()
            }
        }
    }

    // MARK: - Cards

    /// Kopfkarte mit Titel, Autor und ein paar Kennzahlen (Länge, Dauer, Events)
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text(track.title?.isEmpty == false ? track.title! : "(ohne Titel)")
                .font(.obsScreenTitle)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Image(systemName: "person")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(track.author.displayName)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }

            if !track.recordedAt.isEmpty || !track.recordedUntil.isEmpty {
                Text("Aufzeichnung: \(track.recordedAt) – \(track.recordedUntil)")
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                Text(String(format: "Länge: %.2f km", track.length / 1000.0))
                Text("Dauer: \(formattedDuration(track.duration))")
                Text("Events: \(track.numEvents)")
            }
            .font(.obsCaption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .obsCardStyleV2()
    }

    /// Karte mit PortalTrackMapView bzw. Lade-/Fallback-UI
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            OBSSectionHeaderV2("Karte", subtitle: "Tippe auf die Karte für Vollbild.")

            if !mapRoute.isEmpty {
                ZStack(alignment: .topTrailing) {

                    PortalTrackMapView(route: mapRoute, events: mapEvents)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .clipped()
                        .onTapGesture { showFullscreenMap = true }

                    Button { showFullscreenMap = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(10)
                }

            } else if isLoadingMap {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Lade Track-Daten…")
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                }

            } else {
                Button {
                    Task { await loadTrackData() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "map")
                        Text("Karte laden")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .obsCardStyleV2()
    }

    /// Karte mit einklappbaren Details (DisclosureGroup)
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(
                isExpanded: $showDetails,
                content: {
                    VStack(alignment: .leading, spacing: 10) {

                        Group {
                            detailRow(label: "Titel", value: track.title?.isEmpty == false ? track.title! : "(ohne Titel)")
                            detailRow(label: "Portal-ID", value: track.slug)

                            detailRow(label: "Autor", value: track.author.displayName)
                            detailRow(label: "Öffentlich", value: track.isPublic ? "Ja" : "Nein")
                            detailRow(label: "Status", value: track.processingStatus)

                            detailRow(label: "Aufzeichnung von", value: track.recordedAt)
                            detailRow(label: "bis", value: track.recordedUntil)

                            detailRow(label: "Länge", value: String(format: "%.2f km", track.length / 1000.0))
                            detailRow(label: "Dauer", value: formattedDuration(track.duration))

                            detailRow(label: "Events", value: "\(track.numEvents)")
                            detailRow(label: "Gültige Events", value: "\(track.numValid)")
                            detailRow(label: "Messpunkte", value: "\(track.numMeasurements)")
                        }

                        if let desc = track.description, !desc.isEmpty {
                            Divider().padding(.vertical, 2)
                            Text("Beschreibung")
                                .font(.obsBody.weight(.semibold))
                            Text(desc)
                                .font(.obsBody)
                        }

                        if isLoading {
                            Divider().padding(.vertical, 2)
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Lade Details…")
                                    .font(.obsFootnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 6)
                },
                label: {
                    HStack {
                        Text("Details")
                            .font(.obsSectionTitle)
                        Spacer()
                        Text(showDetails ? "Einklappen" : "Ausklappen")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                }
            )
        }
        .obsCardStyleV2()
    }

    // MARK: - Hilfs-UI

    private func detailRow(label: String, value: String?) -> some View {
        let text = (value?.isEmpty == false ? value! : "–")

        return HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.obsFootnote)
                .foregroundStyle(.secondary)

            Spacer()

            Text(text)
                .font(.obsFootnote)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }

    // MARK: - Track-Details nachladen

    private func loadDetail() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let client = PortalApiClient(baseUrl: baseUrl)
            let response = try await client.fetchTrackDetail(slug: initialTrack.slug)

            track = response.track
            errorMessage = nil

            print("PortalTrackDetailView: Details geladen für \(track.slug)")
        } catch let PortalApiError.httpError(status: status, body: body) {
            print("PortalTrackDetailView: httpError \(status) – Body: \(body)")
            errorMessage = "Serverfehler \(status).\nAntwort:\n\(body)"
        } catch {
            print("PortalTrackDetailView: unbekannter Fehler: \(error)")
            errorMessage = "Unbekannter Fehler: \(error.localizedDescription)"
        }
    }

    // MARK: - Track-Daten + Events für Karte laden

    private func loadTrackData() async {
        guard !isLoadingMap else { return }
        isLoadingMap = true
        defer { isLoadingMap = false }

        do {
            let client = PortalApiClient(baseUrl: baseUrl)
            let data = try await client.fetchTrackData(slug: initialTrack.slug)

            let routeCoordinates = extractRoute(from: data.track) ?? extractRoute(from: data.trackRaw) ?? []

            var events: [OvertakeEvent] = []
            if let eventsFC = data.events,
               let features = eventsFC.features {

                for feature in features {
                    guard let geom = feature.geometry,
                          let coords = geom.coordinates,
                          coords.count >= 2
                    else { continue }

                    let lon = coords[0]
                    let lat = coords[1]
                    let distance = feature.properties?.distanceOvertaker

                    let ev = OvertakeEvent(
                        coordinate: .init(latitude: lat, longitude: lon),
                        distance: distance
                    )
                    events.append(ev)
                }
            }

            mapRoute = routeCoordinates
            mapEvents = events
            errorMessage = nil

            print("PortalTrackDetailView: Track-Daten geladen für \(initialTrack.slug) – \(routeCoordinates.count) Punkte, \(events.count) Events")
        } catch let PortalApiError.httpError(status: status, body: body) {
            print("PortalTrackDetailView: httpError (data) \(status) – Body: \(body)")
            errorMessage = "Fehler beim Laden der Track-Daten (\(status)).\nAntwort:\n\(body)"
        } catch {
            print("PortalTrackDetailView: unbekannter Fehler (data): \(error)")
            errorMessage = "Unbekannter Fehler beim Laden der Track-Daten: \(error.localizedDescription)"
        }
    }

    private func extractRoute(from feature: PortalTrackFeature?) -> [CLLocationCoordinate2D]? {
        guard let coords = feature?.geometry?.coordinates, !coords.isEmpty else {
            return nil
        }

        return coords.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            let lon = pair[0]
            let lat = pair[1]
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    // MARK: - Track löschen

    private func deleteTrack() async {
        guard !obsApiKey.isEmpty else {
            errorMessage = "Kein API-Key konfiguriert. Bitte in den Portal-Einstellungen eintragen."
            return
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            let client = PortalApiClient(baseUrl: baseUrl)
            try await client.deleteTrack(slug: initialTrack.slug, apiKey: obsApiKey)

            await MainActor.run {
                Haptics.shared.success()
                NotificationCenter.default.post(name: .portalDataChanged, object: nil)
                dismiss()
            }
        } catch let PortalApiError.httpError(status: status, body: body) {
            if status == 401 || status == 403 {
                errorMessage = "Keine Berechtigung zum Löschen.\nBist du der Eigentümer dieser Fahrt?\n\nAntwort:\n\(body)"
            } else {
                errorMessage = "Fehler beim Löschen (Status \(status)).\nAntwort:\n\(body)"
            }
            Haptics.shared.error()
        } catch {
            errorMessage = "Fehler beim Löschen: \(error.localizedDescription)"
            Haptics.shared.error()
        }
    }
}

// MARK: - Preview

#Preview {
    // Demo-Daten für Xcode Preview
    let author = PortalAuthor(id: 1, displayName: "Demo", bio: nil, image: nil)
    let track = PortalTrackSummary(
        id: 1,
        slug: "demo123",
        title: "Demo-Track",
        description: "Test",
        createdAt: "2025-01-01T00:00:00+0000",
        updatedAt: "2025-01-01T00:00:00+0000",
        isPublic: true,
        processingStatus: "complete",
        recordedAt: "2025-01-01T10:00:00+0000",
        recordedUntil: "2025-01-01T11:00:00+0000",
        duration: 3600,
        length: 12000,
        numEvents: 5,
        numValid: 5,
        numMeasurements: 100,
        author: author
    )

    NavigationStack {
        PortalTrackDetailView(baseUrl: "https://portal.openbikesensor.org", track: track)
    }
}
