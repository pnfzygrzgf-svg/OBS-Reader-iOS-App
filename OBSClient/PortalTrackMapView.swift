import SwiftUI
import MapKit

/// Einfaches Modell für einen Überholvorgang zur Darstellung auf der Karte.
struct OvertakeEvent: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let distance: Double?
}

/// SwiftUI-Wrapper um MKMapView, der
/// - eine Route als Polyline zeichnet
/// - Überholvorgänge als farbige Marker anzeigt
struct PortalTrackMapView: UIViewRepresentable {
    let route: [CLLocationCoordinate2D]
    let events: [OvertakeEvent]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator

        // Ruhigere Karte, ohne POIs
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll

        map.isRotateEnabled = false
        map.showsCompass = false
        map.showsUserLocation = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Alte Inhalte entfernen
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        // Route einzeichnen
        if !route.isEmpty {
            let polyline = MKPolyline(coordinates: route, count: route.count)
            map.addOverlay(polyline)

            // Kartenausschnitt an Route + Events anpassen
            var rect = polyline.boundingMapRect

            if !events.isEmpty {
                let points = events.map { MKMapPoint($0.coordinate) }
                let eventRect = points.reduce(MKMapRect.null) { partial, point in
                    let r = MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0))
                    return partial.isNull ? r : partial.union(r)
                }
                rect = rect.union(eventRect)
            }

            let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
            map.setVisibleMapRect(rect, edgePadding: padding, animated: false)
        }

        // Events als Marker
        for event in events {
            let annotation = OvertakeAnnotation(event: event)
            map.addAnnotation(annotation)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineWidth = 3.0
            renderer.strokeColor = UIColor.systemPink
            renderer.lineDashPattern = [4, 2]   // leicht gestrichelt
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? OvertakeAnnotation else {
                return nil
            }

            let identifier = "overtake"
            let view: MKMarkerAnnotationView

            if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView {
                view = reused
                view.annotation = ann
            } else {
                view = MKMarkerAnnotationView(annotation: ann, reuseIdentifier: identifier)
                view.canShowCallout = true
            }

            // Farbcodeierung nach Abstand
            if let distance = ann.event.distance {
                // 0–1.10 m: dunkelrot
                // 1.11–1.30 m: rot
                // 1.31–1.50 m: gelb
                // 1.51–1.70 m: grün
                // ab 1.71 m: dunkelgrün
                if distance <= 1.10 {
                    view.markerTintColor = UIColor(red: 0.6, green: 0.0, blue: 0.0, alpha: 1.0)
                } else if distance <= 1.30 {
                    view.markerTintColor = .systemRed
                } else if distance <= 1.50 {
                    view.markerTintColor = .systemYellow
                } else if distance <= 1.70 {
                    view.markerTintColor = .systemGreen
                } else {
                    view.markerTintColor = UIColor(red: 0.0, green: 0.4, blue: 0.0, alpha: 1.0)
                }

                view.glyphText = String(format: "%.2f", distance)
            } else {
                // kein Abstand vorhanden → neutral
                view.markerTintColor = .systemGray
                view.glyphText = "–"
            }

            return view
        }
    }
}

// MKAnnotation-Wrapper für einen OvertakeEvent
final class OvertakeAnnotation: NSObject, MKAnnotation {
    let event: OvertakeEvent
    dynamic var coordinate: CLLocationCoordinate2D

    init(event: OvertakeEvent) {
        self.event = event
        self.coordinate = event.coordinate
        super.init()
    }

    var title: String? {
        if let d = event.distance {
            return String(format: "Überholung: %.2f m", d)
        }
        return "Überholung"
    }
}
