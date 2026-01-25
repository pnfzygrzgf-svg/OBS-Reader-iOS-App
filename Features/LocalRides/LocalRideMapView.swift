import SwiftUI
import MapKit

/// Interaktive Karte mit Track-Polyline und klickbaren Event-Markern
struct LocalRideMapView: UIViewRepresentable {
    let ride: LocalRideSession
    let onEventTap: (LocalOvertakeEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEventTap: onEventTap)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Overlays und Annotations aktualisieren
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        // Route als Polyline
        let coords = ride.trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if !coords.isEmpty {
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            map.addOverlay(polyline)
        }

        // Events als Annotationen
        for event in ride.events {
            let annotation = LocalEventAnnotation(event: event)
            map.addAnnotation(annotation)
        }

        // Zoom to fit
        if !coords.isEmpty || !ride.events.isEmpty {
            let rect = calculateBoundingRect(coords: coords, events: ride.events)
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50), animated: false)
        }
    }

    private func calculateBoundingRect(coords: [CLLocationCoordinate2D], events: [LocalOvertakeEvent]) -> MKMapRect {
        var allCoords = coords
        allCoords.append(contentsOf: events.map { $0.coordinate })

        guard !allCoords.isEmpty else {
            return MKMapRect.world
        }

        var rect = MKMapRect.null
        for coord in allCoords {
            let point = MKMapPoint(coord)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            rect = rect.union(pointRect)
        }

        // Etwas Padding hinzufügen
        let padding = rect.size.width * 0.1
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onEventTap: (LocalOvertakeEvent) -> Void

        init(onEventTap: @escaping (LocalOvertakeEvent) -> Void) {
            self.onEventTap = onEventTap
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8)
            renderer.lineWidth = 3
            renderer.lineDashPattern = [6, 3]
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? LocalEventAnnotation else { return nil }

            let identifier = "LocalEventMarker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: ann, reuseIdentifier: identifier)

            view.annotation = ann
            view.canShowCallout = true

            // Farbe basierend auf ThreatLevel oder Distanz
            if let level = ann.event.threatLevel {
                view.markerTintColor = UIColor(level.color)
                view.glyphText = "\(level.rawValue)"
            } else {
                // Unbewertet: Distanz-basierte Farbe
                view.markerTintColor = colorForDistance(ann.event.distanceCm)
                view.glyphText = "\(ann.event.distanceCm)"
            }

            // Tap-Button im Callout
            let btn = UIButton(type: .detailDisclosure)
            view.rightCalloutAccessoryView = btn

            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard let ann = view.annotation as? LocalEventAnnotation else { return }
            onEventTap(ann.event)
        }

        private func colorForDistance(_ cm: Int) -> UIColor {
            switch cm {
            case ..<100:
                return UIColor.systemRed
            case 100..<130:
                return UIColor.systemOrange
            case 130..<150:
                return UIColor.systemYellow
            default:
                return UIColor.systemGreen
            }
        }
    }
}

// MARK: - Annotation

final class LocalEventAnnotation: NSObject, MKAnnotation {
    let event: LocalOvertakeEvent

    var coordinate: CLLocationCoordinate2D { event.coordinate }
    var title: String? { "\(event.distanceCm) cm" }
    var subtitle: String? { event.threatLevel?.displayName ?? "Nicht bewertet" }

    init(event: LocalOvertakeEvent) {
        self.event = event
    }
}

// MARK: - Fullscreen Map

struct LocalRideFullscreenMap: View {
    let ride: LocalRideSession
    let onEventTap: (LocalOvertakeEvent) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LocalRideMapView(ride: ride, onEventTap: onEventTap)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Karte")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
    }
}
