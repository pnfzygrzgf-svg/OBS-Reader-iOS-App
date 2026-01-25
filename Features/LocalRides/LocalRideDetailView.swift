import SwiftUI

/// Wrapper für URL, damit .sheet(item:) funktioniert
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// Detailansicht einer lokalen Fahrt mit Karte und Event-Liste
struct LocalRideDetailView: View {
    let ride: LocalRideSession
    @ObservedObject var store: LocalRideStore

    @State private var selectedEvent: LocalOvertakeEvent?
    @State private var showRatingSheet = false
    @State private var showFullscreenMap = false
    @State private var exportItem: IdentifiableURL?

    // Portal Upload States
    @AppStorage("obsBaseUrl") private var portalBaseUrl: String = ""
    @AppStorage("obsApiKey") private var portalApiKey: String = ""
    @State private var includeRatingsInUpload = true
    @State private var isUploading = false
    @State private var uploadResult: UploadResultState?

    enum UploadResultState {
        case success(String)
        case error(String)
    }

    // Aktuelle Version der Fahrt aus dem Store
    private var currentRide: LocalRideSession {
        store.rides.first { $0.id == ride.id } ?? ride
    }

    var body: some View {
        GroupedScrollScreenV2 {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                mapCard
                eventsSection
                portalUploadSection
            }
        }
        .navigationTitle("Fahrt-Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportRide()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showRatingSheet) {
            if let event = selectedEvent {
                ThreatRatingView(event: event) { level in
                    store.updateEventRating(rideId: ride.id, eventId: event.id, threatLevel: level)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullscreenMap) {
            LocalRideFullscreenMap(ride: currentRide, onEventTap: handleEventTap)
        }
        .sheet(item: $exportItem) { item in
            ActivityView(activityItems: [item.url])
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(formatDate(currentRide.createdAt))
                    .font(.obsScreenTitle)

                Spacer()

                if currentRide.isUploaded {
                    Label("Hochgeladen", systemImage: "checkmark.icloud.fill")
                        .font(.obsCaption)
                        .foregroundStyle(.green)
                }
            }

            // Statistiken
            HStack(spacing: 16) {
                statItem(
                    icon: "exclamationmark.triangle",
                    value: "\(currentRide.events.count)",
                    label: "Events"
                )

                statItem(
                    icon: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath",
                    value: formatDistance(currentRide.totalDistanceMeters),
                    label: "Strecke"
                )

                if let duration = currentRide.durationSeconds {
                    statItem(
                        icon: "clock",
                        value: formatDuration(duration),
                        label: "Dauer"
                    )
                }
            }

            // Bewertungs-Fortschritt
            if !currentRide.events.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Bewertungsfortschritt")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(currentRide.ratedEventsCount) / \(currentRide.events.count)")
                            .font(.obsCaption.weight(.semibold))
                    }

                    ProgressView(value: Double(currentRide.ratedEventsCount), total: Double(currentRide.events.count))
                        .tint(.obsAccentV2)
                }
            }
        }
        .obsCardStyleV2()
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.obsValue)

            Text(label)
                .font(.obsCaption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Map Card

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                OBSSectionHeaderV2("Route", subtitle: "Tippe auf Marker zur Bewertung")
                Spacer()
                Button {
                    showFullscreenMap = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .padding(8)
                        .background(Color.obsCardBorderV2.opacity(0.5))
                        .clipShape(Circle())
                }
            }

            LocalRideMapView(ride: currentRide, onEventTap: handleEventTap)
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .obsCardStyleV2()
    }

    // MARK: - Portal Upload Section

    private var portalUploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OBSSectionHeaderV2("Ins OBS-Portal hochladen")

            // Konfigurationsstatus prüfen
            if portalBaseUrl.isEmpty || portalApiKey.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Portal nicht konfiguriert. Bitte in den Portal-Einstellungen URL und API-Key eintragen.")
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Toggle für Bewertungen
                Toggle(isOn: $includeRatingsInUpload) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bewertungen einschließen")
                            .font(.obsBody)
                        if currentRide.ratedEventsCount > 0 {
                            Text("\(currentRide.ratedEventsCount) von \(currentRide.events.count) Events bewertet")
                                .font(.obsCaption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Noch keine Events bewertet")
                                .font(.obsCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.obsAccentV2)

                Divider()

                // Upload Button
                Button {
                    uploadToPortal()
                } label: {
                    HStack {
                        if isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "icloud.and.arrow.up")
                        }
                        Text(isUploading ? "Wird hochgeladen…" : "Ins Portal hochladen")
                            .font(.obsBody.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUploading)

                // Upload-Ergebnis anzeigen
                if let result = uploadResult {
                    switch result {
                    case .success(let message):
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
                                .font(.obsFootnote)
                                .foregroundStyle(.secondary)
                        }
                    case .error(let message):
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.obsFootnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .obsCardStyleV2()
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OBSSectionHeaderV2("Überholvorgänge", subtitle: "Tippe zum Bewerten")

            if currentRide.events.isEmpty {
                Text("Keine Überholvorgänge aufgezeichnet.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(currentRide.events) { event in
                    Button {
                        handleEventTap(event)
                    } label: {
                        eventRow(event)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .obsCardStyleV2()
    }

    private func eventRow(_ event: LocalOvertakeEvent) -> some View {
        HStack(spacing: 12) {
            // Bewertungs-Badge
            Circle()
                .fill(event.threatLevel?.color ?? Color.gray.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay {
                    if let level = event.threatLevel {
                        Text("\(level.rawValue)")
                            .font(.callout.bold())
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "questionmark")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(event.distanceCm) cm")
                        .font(.obsSectionTitle)

                    // Distanz-basierte Warnung
                    if event.distanceCm < 150 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(event.distanceCm < 100 ? .red : .orange)
                    }
                }

                Text(formatTime(event.timestamp))
                    .font(.obsCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(event.threatLevel?.displayName ?? "Bewerten")
                .font(.obsFootnote)
                .foregroundStyle(event.threatLevel != nil ? Color.primary : Color.obsAccentV2)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func handleEventTap(_ event: LocalOvertakeEvent) {
        selectedEvent = event
        showRatingSheet = true
    }

    private func uploadToPortal() {
        guard !portalBaseUrl.isEmpty, !portalApiKey.isEmpty else { return }

        // GeoJSON exportieren (mit oder ohne Bewertungen)
        guard let geoJSONData = store.exportAsGeoJSON(currentRide, includeRatings: includeRatingsInUpload) else {
            uploadResult = .error("GeoJSON konnte nicht erstellt werden")
            return
        }

        // Dateiname generieren
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: currentRide.createdAt)
        let fileName = "ride_\(stamp).geojson"

        isUploading = true
        uploadResult = nil

        Task {
            do {
                let result = try await OBSUploader.shared.uploadGeoJSON(
                    geoJSONData: geoJSONData,
                    fileName: fileName,
                    baseUrl: portalBaseUrl,
                    apiKey: portalApiKey
                )

                await MainActor.run {
                    isUploading = false
                    if result.isSuccessful {
                        store.markAsUploaded(rideId: currentRide.id)
                        uploadResult = .success("Fahrt erfolgreich hochgeladen!")
                    } else {
                        // HTTP-Fehler interpretieren
                        switch result.statusCode {
                        case 401:
                            uploadResult = .error("Authentifizierung fehlgeschlagen. Bitte API-Key prüfen.")
                        case 413:
                            uploadResult = .error("Datei zu groß für den Server.")
                        case 500...599:
                            uploadResult = .error("Server-Fehler (\(result.statusCode)). Bitte später erneut versuchen.")
                        default:
                            uploadResult = .error("Fehler \(result.statusCode): \(result.responseBody)")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadResult = .error("Netzwerkfehler: \(error.localizedDescription)")
                }
            }
        }
    }

    private func exportRide() {
        guard let data = store.exportAsGeoJSON(currentRide) else {
            print("Export-Fehler: GeoJSON konnte nicht erstellt werden")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: currentRide.createdAt)

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("ride_\(stamp)_export.geojson")

        do {
            try data.write(to: url)
            exportItem = IdentifiableURL(url: url)
        } catch {
            print("Export-Fehler: \(error)")
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins >= 60 {
            let hours = mins / 60
            let remainingMins = mins % 60
            return "\(hours):\(String(format: "%02d", remainingMins)) h"
        }
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
