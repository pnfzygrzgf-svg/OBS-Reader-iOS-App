// LocationManager.swift

import Foundation
import CoreLocation
import Combine

/// Kapselt den CoreLocation-Manager und leitet GPS-Updates
/// an den BluetoothManager weiter, damit dieser Geolocation-Events
/// in die BIN-Datei schreiben kann.
///
/// Aufgaben:
/// - Standortberechtigungen beobachten
/// - Hintergrund-GPS konfigurieren
/// - letzte bekannte Position veröffentlichen (`@Published lastLocation`)
/// - bei neuen Positionen: `bluetoothManager.handleLocationUpdate(_:)` aufrufen
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// Aktueller Authorization-Status (für UI/Debug)
    @Published var authorizationStatus: CLAuthorizationStatus
    /// Letzte von iOS gemeldete Position
    @Published var lastLocation: CLLocation?

    /// Interner CoreLocation-Manager
    private let manager: CLLocationManager
    /// Referenz auf den BluetoothManager, um GPS-Updates in die Aufnahmelogik zu geben
    /// `unowned`, weil BluetoothManager den LocationManager erstellt und länger lebt.
    private unowned let bluetoothManager: BluetoothManager

    /// Initialisiert den LocationManager und konfiguriert CoreLocation.
    ///
    /// - Parameter bluetoothManager:
    ///   Referenz, um GPS-Updates direkt an die BIN-Schreiblogik zu delegieren.
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager

        let manager = CLLocationManager()
        self.manager = manager
        // Initialen Berechtigungsstatus abfragen
        self.authorizationStatus = manager.authorizationStatus

        super.init()

        // Delegate setzen, damit wir Callbacks erhalten
        manager.delegate = self

        // GPS-Einstellungen: hohe Genauigkeit, alle Updates
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone

        //  WICHTIG für Hintergrund:
        // - darf im Hintergrund weiterlaufen
        manager.allowsBackgroundLocationUpdates = true
        // - iOS soll nicht „automatisch pausieren“
        manager.pausesLocationUpdatesAutomatically = false

        //  Statt "WhenInUse" jetzt "Always" anfragen,
        // damit im Hintergrund aufgezeichnet werden kann.
        manager.requestAlwaysAuthorization()

        // Falls schon erlaubt war, direkt Standort-Updates starten
        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    /// Wird aufgerufen, wenn sich die Location-Berechtigung ändert
    /// (z. B. durch Systemdialog oder Einstellungen).
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        // Status ins @Published-Property spiegeln (auf dem Main-Thread für das UI)
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            // Sicherheitshalber nochmal setzen, falls iOS den Manager neu konfiguriert hat
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.startUpdatingLocation()

        case .denied, .restricted:
            // Nutzer hat abgelehnt oder es ist anderweitig untersagt
            manager.stopUpdatingLocation()

        case .notDetermined:
            // User hat noch keine Entscheidung getroffen -> nichts tun
            break

        @unknown default:
            // Für zukünftige, unbekannte Statuswerte: lieber nichts tun
            break
        }
    }

    /// Wird aufgerufen, wenn neue Standortdaten verfügbar sind.
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        // wir nehmen die letzte (aktuellste) Position aus dem Array
        guard let loc = locations.last else { return }

        // letzte Position im Published-Property aktualisieren (für UI/Debug)
        DispatchQueue.main.async {
            self.lastLocation = loc
        }

        // Hier werden die Geolocation-Events erzeugt und in die BIN geschrieben.
        // BluetoothManager kümmert sich um Distanzberechnung + Event-Schreiben.
        bluetoothManager.handleLocationUpdate(loc)
    }

    /// Fehler-Callback vom CoreLocation-Manager.
    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        print("LocationManager error: \(error)")
    }
}
