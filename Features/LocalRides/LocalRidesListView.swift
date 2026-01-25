import SwiftUI

/// Liste aller lokalen Fahrten mit Bewertungsmöglichkeit
struct LocalRidesListView: View {
    @StateObject private var store = LocalRideStore()
    @State private var rideToDelete: LocalRideSession?
    @State private var showDeleteConfirmation = false

    var body: some View {
        GroupedScrollScreenV2 {
            VStack(alignment: .leading, spacing: 12) {
                OBSSectionHeaderV2(
                    "Lokale Fahrten",
                    subtitle: "Fahrten mit Bedrohungsbewertung ansehen und bearbeiten."
                )

                if store.isLoading {
                    loadingState
                } else if store.rides.isEmpty {
                    emptyState
                } else {
                    ridesList
                }
            }
        }
        .navigationTitle("Lokale Fahrten")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.loadRides() }
        .refreshable { store.loadRides() }
        .confirmationDialog(
            "Fahrt löschen?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let ride = rideToDelete {
                    store.deleteRide(ride)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Diese Fahrt und alle Bewertungen werden unwiderruflich gelöscht.")
        }
    }

    // MARK: - States

    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding()
            Spacer()
        }
        .obsCardStyleV2()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("Keine lokalen Fahrten")
                .font(.obsSectionTitle)

            Text("Starte eine Aufnahme, um Fahrten mit Bedrohungsbewertung zu speichern.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .obsCardStyleV2()
    }

    private var ridesList: some View {
        ForEach(store.rides) { ride in
            NavigationLink {
                LocalRideDetailView(ride: ride, store: store)
            } label: {
                rideRow(ride)
            }
            .buttonStyle(.plain)
            .obsCardStyleV2()
            .contextMenu {
                Button(role: .destructive) {
                    rideToDelete = ride
                    showDeleteConfirmation = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Row

    private func rideRow(_ ride: LocalRideSession) -> some View {
        HStack(spacing: 12) {
            // Icon mit Bewertungsfortschritt
            ZStack {
                Circle()
                    .stroke(Color.obsCardBorderV2, lineWidth: 2)
                    .frame(width: 44, height: 44)

                if ride.events.isEmpty {
                    Image(systemName: "bicycle")
                        .foregroundStyle(.secondary)
                } else {
                    let progress = Double(ride.ratedEventsCount) / Double(ride.events.count)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.obsAccentV2, lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))

                    Text("\(ride.ratedEventsCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(formatDate(ride.createdAt))
                        .font(.obsSectionTitle)

                    if ride.isUploaded {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 8) {
                    Label("\(ride.events.count)", systemImage: "exclamationmark.triangle")
                    Label(formatDistance(ride.totalDistanceMeters), systemImage: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath")

                    if ride.ratedEventsCount < ride.events.count {
                        Text("\(ride.events.count - ride.ratedEventsCount) offen")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.obsCaption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
}
