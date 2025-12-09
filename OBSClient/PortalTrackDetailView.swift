import SwiftUI
import CoreLocation

struct PortalTrackDetailView: View {
    let baseUrl: String
    let initialTrack: PortalTrackSummary

    @State private var track: PortalTrackSummary
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Für die Karte
    @State private var mapRoute: [CLLocationCoordinate2D] = []
    @State private var mapEvents: [OvertakeEvent] = []
    @State private var isLoadingMap = false

    // Details ein-/ausklappbar
    @State private var showDetails = true

    init(baseUrl: String, track: PortalTrackSummary) {
        self.baseUrl = baseUrl
        self.initialTrack = track
        _track = State(initialValue: track)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Titel / Slug
                Text(track.title?.isEmpty == false ? track.title! : "(ohne Titel)")
                    .font(.title2)
                    .bold()

                Text("Slug: \(track.slug)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                // MARK: Karte

                Divider().padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Karte")
                        .font(.headline)

                    if !mapRoute.isEmpty {
                        PortalTrackMapView(route: mapRoute, events: mapEvents)
                            .frame(height: 300)
                            .cornerRadius(12)
                            .clipped()
                    } else if isLoadingMap {
                        HStack {
                            ProgressView()
                            Text("Lade Track-Daten…")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Button("Karte laden") {
                            Task { await loadTrackData() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // MARK: einklappbare Details

                Divider().padding(.vertical, 8)

                DisclosureGroup(
                    isExpanded: $showDetails,
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            Group {
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
                                Divider().padding(.vertical, 4)
                                Text("Beschreibung")
                                    .font(.headline)
                                Text(desc)
                            }

                            if isLoading {
                                Divider().padding(.vertical, 4)
                                HStack {
                                    ProgressView()
                                    Text("Lade Details…")
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    },
                    label: {
                        HStack {
                            Text("Details")
                                .font(.headline)
                            Spacer()
                            Text(showDetails ? "Einklappen" : "Ausklappen")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                )
            }
            .padding()
        }
        .navigationTitle("Track-Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
            await loadTrackData()
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

    // MARK: - Hilfs-UI

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
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
        } catch let PortalApiError.httpError(status, body) {
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

            // Route: bevorzugt "track" (gesnappt), Fallback auf "trackRaw"
            let routeCoordinates = extractRoute(from: data.track) ?? extractRoute(from: data.trackRaw) ?? []

            // Events: alle Feature-Punkte
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
        } catch let PortalApiError.httpError(status, body) {
            print("PortalTrackDetailView: httpError (data) \(status) – Body: \(body)")
            errorMessage = "Fehler beim Laden der Track-Daten (\(status)).\nAntwort:\n\(body)"
        } catch {
            print("PortalTrackDetailView: unbekannter Fehler (data): \(error)")
            errorMessage = "Unbekannter Fehler beim Laden der Track-Daten: \(error.localizedDescription)"
        }
    }

    /// Nimmt ein GeoJSON-Feature mit LineString-Geometrie
    /// und baut eine Liste von CLLocationCoordinate2D daraus.
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
}

// MARK: - Preview

#Preview {
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

    return NavigationView {
        PortalTrackDetailView(baseUrl: "https://portal.openbikesensor.org", track: track)
    }
}
