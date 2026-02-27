// SPDX-License-Identifier: GPL-3.0-or-later

// LocalTrackDetailView.swift

import SwiftUI
import CoreLocation

/// Detailansicht für eine lokale Fahrt.
/// Zeigt:
/// - Kopfkarte (Dateiname, Statistiken)
/// - Karte mit Route + Event-Markern
struct LocalTrackDetailView: View {

    let file: OBSFileInfo

    @State private var trackData: LocalTrackData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFullscreenMap = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    mapCard
                    statsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Fahrt-Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTrackData()
        }
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(isPresented: $showFullscreenMap) {
            if let data = trackData {
                ZStack(alignment: .topTrailing) {
                    PortalTrackMapView(route: data.route, events: data.events)
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
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(file.name)
                .font(.obsScreenTitle)
                .lineLimit(2)

            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text("\(file.sizeDescription) · \(file.dateDescription)")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .obsCardStyleV2()
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            OBSSectionHeaderV2("Karte", subtitle: "Tippe für Vollbild.")

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Lade Track-Daten...")
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if let data = trackData, !data.route.isEmpty {
                ZStack(alignment: .topTrailing) {
                    PortalTrackMapView(route: data.route, events: data.events)
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
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)

                    Text("Keine GPS-Daten vorhanden")
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .obsCardStyleV2()
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            OBSSectionHeaderV2("Statistiken")

            if let data = trackData {
                HStack(spacing: 24) {
                    StatColumn(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        value: String(format: "%.2f km", data.distanceMeters / 1000.0),
                        label: "Distanz"
                    )

                    StatColumn(
                        icon: "car.side",
                        value: "\(data.events.count)",
                        label: "Events"
                    )

                    StatColumn(
                        icon: "waveform.path",
                        value: "\(data.measurementCount)",
                        label: "Messpunkte"
                    )
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Keine Daten verfügbar")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }
        }
        .obsCardStyleV2()
    }

    // MARK: - Load Data

    private func loadTrackData() async {
        isLoading = true

        do {
            let data = try LocalTrackParser.parse(fileURL: file.url)
            await MainActor.run {
                self.trackData = data
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

// MARK: - Stat Column

private struct StatColumn: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.obsBody.weight(.semibold))
                    .monospacedDigit()
            }
            Text(label)
                .font(.obsCaption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        LocalTrackDetailView(file: OBSFileInfo(
            url: URL(fileURLWithPath: "/test.csv"),
            name: "fahrt_20250101_120000.csv",
            sizeDescription: "1.2 MB",
            dateDescription: "01.01.2025, 12:00",
            modificationDate: Date(),
            overtakeCount: 5,
            distanceKm: 12.5
        ))
    }
}
