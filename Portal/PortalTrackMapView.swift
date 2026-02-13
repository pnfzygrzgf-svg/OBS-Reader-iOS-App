// PortalTrackMapView.swift

import SwiftUI
import MapKit

/// Datenmodell für ein Überhol-Event, das als Marker auf der Karte angezeigt wird.
/// - Identifiable: damit SwiftUI/Listen etc. eindeutige IDs nutzen können
struct OvertakeEvent: Identifiable {
    // Eindeutige ID pro Event (für SwiftUI-Diffs/Updates)
    let id = UUID()

    // Position des Events auf der Karte
    let coordinate: CLLocationCoordinate2D

    // Optionaler Abstand (z.B. gemessener Überholabstand); kann fehlen
    let distance: Double?
}

/// SwiftUI-Wrapper um MKMapView.
/// Zeichnet:
/// - eine Route als Polyline
/// - Event-Marker als Annotationen
///
/// OPTIK-UPDATE:
/// - Route als systemBlue (statt Pink) + etwas weicher (alpha)
/// - Marker: klarere Farb-Skala + glyphText bleibt Distanz
/// - Callout mit sauberem Title
struct PortalTrackMapView: UIViewRepresentable {

    /// Route als Liste von Koordinaten (Polyline)
    let route: [CLLocationCoordinate2D]

    /// Events entlang der Route (als Marker)
    let events: [OvertakeEvent]

    /// Coordinator verbindet UIKit-Delegates mit SwiftUI (hier: MKMapViewDelegate).
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Erstellt die MKMapView einmalig.
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()

        // Delegate wird benötigt, um Overlays (Polyline) und Annotation-Views zu stylen
        map.delegate = context.coordinator

        // Dezenter Kartenstil (weniger „knallig“)
        map.mapType = .mutedStandard

        // Keine POIs (Points of Interest) anzeigen, damit die Route im Fokus bleibt
        map.pointOfInterestFilter = .excludingAll

        // UI/Interaktion einschränken für eine „statische“ Darstellung
        map.isRotateEnabled = false
        map.showsCompass = false
        map.showsUserLocation = false

        return map
    }

    /// Wird aufgerufen, wenn SwiftUI-State (route/events) sich ändert.
    /// Hier werden Overlays/Annotationen aktualisiert.
    func updateUIView(_ map: MKMapView, context: Context) {
        // Vorherige Zeichnungen entfernen, damit wir sauber neu zeichnen
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        // Wenn eine Route existiert, zeichnen wir eine Polyline und zoomen passend hinein
        if !route.isEmpty {
            // Polyline aus Koordinaten erzeugen und als Overlay hinzufügen
            let polyline = MKPolyline(coordinates: route, count: route.count)
            map.addOverlay(polyline)

            // Bounding-Rect der Route ermitteln (für „zoom to fit“)
            var rect = polyline.boundingMapRect

            // Wenn Events existieren, nehmen wir deren Bounding-Rect dazu,
            // damit auch Marker sicher im sichtbaren Bereich sind.
            if !events.isEmpty {
                let points = events.map { MKMapPoint($0.coordinate) }

                // Aus allen Punkten ein umschließendes Rect bauen
                let eventRect = points.reduce(MKMapRect.null) { partial, point in
                    // Ein „Rect“ aus einem einzelnen Punkt
                    let r = MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0))
                    // union fügt das Rect zum bisherigen Gesamt-Rect hinzu
                    return partial.isNull ? r : partial.union(r)
                }

                // Route-Rect und Event-Rect zusammenführen
                rect = rect.union(eventRect)
            }

            // Padding, damit Route/Marker nicht am Rand kleben
            let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)

            // Sichtbereich setzen ohne Animation (damit es nicht „springt“)
            map.setVisibleMapRect(rect, edgePadding: padding, animated: false)
        }

        // Alle Events als Annotationen hinzufügen (Marker)
        for event in events {
            let annotation = OvertakeAnnotation(event: event)
            map.addAnnotation(annotation)
        }
    }

    /// Coordinator implementiert MKMapViewDelegate:
    /// - Styling für Polyline (Overlay)
    /// - Styling für Marker (Annotation Views)
    class Coordinator: NSObject, MKMapViewDelegate {

        /// Wird von MapKit aufgerufen, um einen Renderer für Overlays zu liefern.
        /// Hier wird die Linienoptik (Farbe, Strichbreite, Dash-Pattern) definiert.
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Wir erwarten hier eine Polyline; andere Overlay-Typen werden „neutral“ gerendert
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            // Renderer für Polyline erstellen
            let renderer = MKPolylineRenderer(polyline: polyline)

            // Linienbreite in Punkten
            renderer.lineWidth = 3.0

            // Optik: systemBlue statt Pink (passt besser zu iOS)
            renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.85)

            // Optional: leichte Strichelung (wirkt "GPS-ish")
            renderer.lineDashPattern = [6, 3]

            return renderer
        }

        /// Wird aufgerufen, um die Darstellung einer Annotation zu konfigurieren.
        /// Wir verwenden MKMarkerAnnotationView, damit wir farbige Marker + Text (glyph) anzeigen können.
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Nur unsere eigenen Annotationen rendern
            guard let ann = annotation as? OvertakeAnnotation else { return nil }

            // Reuse-Identifier für View-Recycling (Performance)
            let identifier = "overtake"
            let view: MKMarkerAnnotationView

            // Wenn möglich, vorhandene View wiederverwenden
            if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView {
                view = reused
                view.annotation = ann
            } else {
                // Sonst neu erstellen
                view = MKMarkerAnnotationView(annotation: ann, reuseIdentifier: identifier)
                view.canShowCallout = true // Tippen zeigt Title/Callout an
            }

            // Marker-Farbe & Glyph je nach Abstand (distance) festlegen
            if let distance = ann.event.distance {
                // Farbskala nach „kritisch" → „ok" (zentralisiert in OBSOvertakeThresholds)
                view.markerTintColor = OBSOvertakeThresholds.uiColor(for: distance)

                // Text im Marker (Glyph) – hier: Distanz mit 2 Nachkommastellen
                view.glyphText = String(format: "%.2f", distance)
            } else {
                // Keine Distanz vorhanden → neutraler Marker
                view.markerTintColor = .systemGray
                view.glyphText = "–"
            }

            return view
        }
    }
}

/// Eigene Annotation-Klasse, damit wir ein Event-Objekt am Marker „dranhängen“ können.
/// MKAnnotation verlangt u.a. eine `coordinate`-Property.
final class OvertakeAnnotation: NSObject, MKAnnotation {

    /// Referenz auf das zugrunde liegende Event (enthält Koordinate + Distanz)
    let event: OvertakeEvent

    /// Coordinate muss dynamisch sein, damit MapKit Änderungen beobachten kann
    dynamic var coordinate: CLLocationCoordinate2D

    init(event: OvertakeEvent) {
        self.event = event
        self.coordinate = event.coordinate
        super.init()
    }

    /// Titel für den Callout (Popup) bei Tap auf den Marker
    var title: String? {
        if let d = event.distance {
            return String(format: "Überholung: %.2f m", d)
        }
        return "Überholung"
    }
}
