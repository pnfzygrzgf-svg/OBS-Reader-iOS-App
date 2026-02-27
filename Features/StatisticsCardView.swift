// SPDX-License-Identifier: GPL-3.0-or-later

// StatisticsCardView.swift

import SwiftUI

/// Statistik-Karte für die PortalHomeView.
/// Zeigt Gesamtübersicht:
/// - Lokale Fahrten (aus Documents)
/// - Portal-Fahrten (aus API)
struct StatisticsCardView: View {

    @AppStorage("obsBaseUrl") private var obsBaseUrl: String = ""

    @State private var localStats: TotalStats = TotalStats()
    @State private var portalStats: TotalStats = TotalStats()
    @State private var isLoadingLocal = true
    @State private var isLoadingPortal = false

    /// Refresh-Trigger: wird erhöht um Neuladen zu erzwingen
    @State private var refreshID = UUID()

    private var isLoading: Bool {
        isLoadingLocal || isLoadingPortal
    }

    private var hasAnyStats: Bool {
        localStats.trackCount > 0 || portalStats.trackCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OBSSpacing.lg) {
            // Header
            HStack(spacing: OBSSpacing.md) {
                Image(systemName: "chart.bar.fill")
                    .font(.title3)
                    .foregroundStyle(Color.obsAccentV2)

                Text("Deine Statistik")
                    .font(.obsSectionTitle)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if !hasAnyStats && !isLoading {
                Text("Noch keine Fahrten aufgezeichnet.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: OBSSpacing.lg) {
                    // Lokale Statistik
                    if localStats.trackCount > 0 {
                        statsRow(
                            title: "Lokal",
                            stats: localStats
                        )
                    }

                    // Portal-Statistik
                    if portalStats.trackCount > 0 {
                        statsRow(
                            title: "Portal",
                            stats: portalStats
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .obsCardStyleV2()
        .task(id: refreshID) {
            // Beide Ladevorgänge parallel und im Hintergrund
            async let localTask: () = loadLocalStatsAsync()
            async let portalTask: () = loadPortalStatsAsync()
            _ = await (localTask, portalTask)
        }
        .onReceive(NotificationCenter.default.publisher(for: .portalDataChanged)) { _ in
            refreshID = UUID()
        }
    }

    // MARK: - Stats Row

    private func statsRow(title: String, stats: TotalStats) -> some View {
        VStack(alignment: .leading, spacing: OBSSpacing.sm) {
            Text(title)
                .font(.obsCaption)
                .foregroundStyle(.secondary)

            HStack(spacing: OBSSpacing.xl) {
                StatItemWithIcon(
                    icon: "bicycle",
                    value: "\(stats.trackCount)",
                    label: stats.trackCount == 1 ? "Fahrt" : "Fahrten"
                )

                StatItemWithIcon(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    value: String(format: "%.1f", stats.totalDistanceKm),
                    label: "km"
                )

                StatItemWithIcon(
                    icon: "car.side",
                    value: "\(stats.totalOvertakes)",
                    label: "Events"
                )
            }
        }
    }

    // MARK: - Load Data

    private func loadLocalStatsAsync() async {
        await MainActor.run { isLoadingLocal = true }

        // Im Hintergrund laden, um Main-Thread nicht zu blockieren
        let stats = await Task.detached(priority: .userInitiated) {
            OvertakeStatsStore.loadAll()
        }.value

        await MainActor.run {
            localStats = stats
            isLoadingLocal = false
        }
    }

    private func loadPortalStatsAsync() async {
        guard !obsBaseUrl.isEmpty else { return }

        await MainActor.run { isLoadingPortal = true }

        do {
            let client = PortalApiClient(baseUrl: obsBaseUrl)
            let result = try await client.fetchMyTracks(limit: 100)

            let totalKm = result.tracks.reduce(0.0) { $0 + $1.length / 1000.0 }
            let totalEvents = result.tracks.reduce(0) { $0 + $1.numEvents }

            await MainActor.run {
                portalStats = TotalStats(
                    trackCount: result.tracks.count,
                    totalDistanceKm: totalKm,
                    totalOvertakes: totalEvents
                )
                isLoadingPortal = false
            }
        } catch {
            await MainActor.run {
                isLoadingPortal = false
            }
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Wird gepostet, wenn Portal-Daten geändert wurden (z.B. Track gelöscht)
    static let portalDataChanged = Notification.Name("portalDataChanged")
}

// MARK: - Stat Item with Icon

private struct StatItemWithIcon: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: OBSSpacing.xs) {
            HStack(spacing: OBSSpacing.xs) {
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

// MARK: - Total Stats

struct TotalStats {
    var trackCount: Int = 0
    var totalDistanceKm: Double = 0.0
    var totalOvertakes: Int = 0
}

// MARK: - OvertakeStatsStore Extension

extension OvertakeStatsStore {
    /// Lädt alle gespeicherten Statistiken und summiert sie.
    static func loadAll() -> TotalStats {
        let countsDict = UserDefaults.standard.dictionary(forKey: "obsOvertakeCounts") as? [String: Int] ?? [:]
        let distDict = UserDefaults.standard.dictionary(forKey: "obsTrackDistanceMeters") as? [String: Double] ?? [:]

        // Alle bekannten Dateien (aus beiden Dictionaries)
        let allKeys = Set(countsDict.keys).union(Set(distDict.keys))

        // Nur Dateien zählen, die noch im Documents-Ordner existieren
        let fm = FileManager.default
        guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return TotalStats()
        }

        var trackCount = 0
        var totalDistanceKm = 0.0
        var totalOvertakes = 0

        for key in allKeys {
            let fileURL = docsURL.appendingPathComponent(key)
            guard fm.fileExists(atPath: fileURL.path) else { continue }

            trackCount += 1

            if let count = countsDict[key] {
                totalOvertakes += count
            }

            if let meters = distDict[key] {
                totalDistanceKm += meters / 1000.0
            }
        }

        return TotalStats(
            trackCount: trackCount,
            totalDistanceKm: totalDistanceKm,
            totalOvertakes: totalOvertakes
        )
    }
}

#Preview {
    VStack {
        StatisticsCardView()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
