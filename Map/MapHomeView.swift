// SPDX-License-Identifier: GPL-3.0-or-later

// MapHomeView.swift

import SwiftUI
import MapKit

struct MapHomeView: View {

    @EnvironmentObject var bt: BluetoothManager

    @State private var recenterToken: Int = 0
    @State private var showClearConfirm: Bool = false
    @State private var isMapReady: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            if isMapReady {
                LiveOvertakeMapView(
                    events: bt.liveOvertakeEvents,
                    recenterToken: $recenterToken
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else {
                // Placeholder während MapKit lädt
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Karte wird geladen...")
                                .font(.obsFootnote)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            // Overlay unten links: letzter Überholvorgang
            VStack(alignment: .leading, spacing: 4) {
                Text("Letzter Überholvorgang")
                    .font(.obsFootnote.weight(.semibold))

                if let cm = bt.overtakeDistanceCm {
                    Text("\(cm) cm")
                        .font(.obsSectionTitle)
                        .monospacedDigit()
                } else {
                    Text("–")
                        .font(.obsSectionTitle)
                }

                if let t = bt.lastOvertakeAt {
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(radius: 3)
            .padding(.leading, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)

            // Floating Button unten rechts: Zentrieren
            Button {
                recenterToken &+= 1
            } label: {
                Image(systemName: "scope")
                    .font(.title3)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .accessibilityLabel("Zentrieren")
        }
        .navigationTitle("Karte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(bt.liveOvertakeEvents.isEmpty)
                .accessibilityLabel("Marker löschen")
            }
        }
        .alert("Marker löschen?", isPresented: $showClearConfirm) {
            Button("Löschen", role: .destructive) {
                bt.clearLiveOvertakeEvents()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Überholvorgang-Punkte werden von der Karte entfernt.")
        }
        .task {
            // Kurze Verzögerung damit UI den Lade-Zustand anzeigen kann
            // bevor MapKit den Main-Thread blockiert
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            withAnimation(.easeIn(duration: 0.2)) {
                isMapReady = true
            }
        }
    }
}

// MARK: - UIKit Map Wrapper

private struct LiveOvertakeMapView: UIViewRepresentable {

    let events: [OvertakeEvent]
    @Binding var recenterToken: Int

    /// Radius ~ 1.5 km (1500 m)
    private let initialMeters: CLLocationDistance = 1500

    func makeCoordinator() -> Coordinator {
        Coordinator(initialMeters: initialMeters)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator

        // Ruhiger Stil + keine POIs
        if #available(iOS 17.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic = false
            map.preferredConfiguration = config
        } else {
            map.mapType = .mutedStandard
            map.pointOfInterestFilter = .excludingAll
        }

        // Blauer Punkt
        map.showsUserLocation = true

        // UI
        map.showsCompass = false
        map.showsScale = false

        // Interaktion
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = true
        map.isPitchEnabled = true

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {

        // Nur unsere Annotationen ersetzen (UserLocation bleibt)
        let existing = map.annotations.compactMap { $0 as? OvertakeAnnotation }
        map.removeAnnotations(existing)

        let anns = events.map { OvertakeAnnotation(event: $0) }
        map.addAnnotations(anns)

        // One-shot Zentrieren (Button) mit definiertem Zoom (~1.5 km)
        if context.coordinator.lastRecenterToken != recenterToken {
            context.coordinator.lastRecenterToken = recenterToken

            if let coord = map.userLocation.location?.coordinate {
                let region = MKCoordinateRegion(
                    center: coord,
                    latitudinalMeters: initialMeters,
                    longitudinalMeters: initialMeters
                )
                map.setRegion(region, animated: true)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastRecenterToken: Int = 0
        var didSetInitialRegion: Bool = false
        let initialMeters: CLLocationDistance

        init(initialMeters: CLLocationDistance) {
            self.initialMeters = initialMeters
        }

        //  Sobald die UserLocation wirklich da ist: Initial-Zoom setzen (einmalig)
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didSetInitialRegion,
                  let coord = userLocation.location?.coordinate
            else { return }

            didSetInitialRegion = true

            let region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: initialMeters,
                longitudinalMeters: initialMeters
            )
            mapView.setRegion(region, animated: false)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // System-UserLocation (blauer Punkt) nicht überschreiben
            if annotation is MKUserLocation { return nil }

            guard let ann = annotation as? OvertakeAnnotation else { return nil }

            let identifier = "overtake"
            let view: MKMarkerAnnotationView

            if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView {
                view = reused
                view.annotation = ann
            } else {
                view = MKMarkerAnnotationView(annotation: ann, reuseIdentifier: identifier)
                view.canShowCallout = true
            }

            if let distance = ann.event.distance {
                // Farbskala zentralisiert in OBSOvertakeThresholds
                view.markerTintColor = OBSOvertakeThresholds.uiColor(for: distance)
                view.glyphText = String(format: "%.2f", distance)
            } else {
                view.markerTintColor = .systemGray
                view.glyphText = "–"
            }

            return view
        }
    }
}
