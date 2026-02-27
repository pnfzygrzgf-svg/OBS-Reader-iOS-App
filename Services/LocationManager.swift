// SPDX-License-Identifier: GPL-3.0-or-later

// LocationManager.swift

import Foundation
import CoreLocation
import Combine

/// Kapselt CoreLocation in einer eigenen Klasse und leitet GPS-Updates
/// an den BluetoothManager weiter.
///
/// Wozu?
/// - UI kann Location-Status und letzte Position beobachten (`@Published`)
/// - CoreLocation-Konfiguration ist an einer Stelle gebündelt
/// - BluetoothManager bekommt neue Positionen über `handleLocationUpdate(_:)`,
///   um Distanz zu zählen und (im Lite-Modus) Geolocation-Events in die BIN zu schreiben.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // =====================================================
    // MARK: - Published (für SwiftUI)
    // =====================================================

    /// Aktueller Authorization-Status (für UI/Debug und Permission-Hinweise).
    @Published var authorizationStatus: CLAuthorizationStatus

    /// Letzte von iOS gemeldete Position (z.B. für Debug/Anzeige).
    @Published var lastLocation: CLLocation?

    // =====================================================
    // MARK: - Private Properties
    // =====================================================

    /// Interner CoreLocation-Manager, der die eigentlichen GPS-Updates liefert.
    private let manager: CLLocationManager

    /// Referenz auf den BluetoothManager, damit GPS-Updates in die Aufnahmelogik fließen.
    /// `weak` um Crashes zu vermeiden falls BluetoothManager früher freigegeben wird.
    private weak var bluetoothManager: BluetoothManager?

    // =====================================================
    // MARK: - Init / Setup
    // =====================================================

    /// Initialisiert den LocationManager und konfiguriert CoreLocation.
    ///
    /// - Parameter bluetoothManager:
    ///   Referenz, um GPS-Updates direkt an die Aufnahmelogik zu delegieren.
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager

        // CLLocationManager erzeugen
        let manager = CLLocationManager()
        self.manager = manager

        // Initialen Berechtigungsstatus abfragen (wird für UI veröffentlicht)
        self.authorizationStatus = manager.authorizationStatus

        super.init()

        // Delegate setzen, damit wir Callbacks bekommen (Auth-Änderung, Locations, Fehler)
        manager.delegate = self

        // GPS-Einstellungen:
        // - bestmögliche Genauigkeit (kann mehr Akku kosten)
        manager.desiredAccuracy = kCLLocationAccuracyBest

        // - keine Mindestdistanz: jedes Update kommt durch (kann mehr Updates erzeugen)
        manager.distanceFilter = kCLDistanceFilterNone

        // WICHTIG für Hintergrund-Aufzeichnung:
        // - erlaubt Updates im Hintergrund (setzt iOS-Entitlements/Info.plist voraus!)
        manager.allowsBackgroundLocationUpdates = true

        // - iOS soll Updates nicht automatisch pausieren (stabiler, aber mehr Akku)
        manager.pausesLocationUpdatesAutomatically = false

        // „Always“ anfragen, damit auch bei gesperrtem Bildschirm / Hintergrund aufgezeichnet werden kann.
        // (setzt passende Info.plist Keys voraus: NSLocationAlwaysAndWhenInUseUsageDescription etc.)
        manager.requestAlwaysAuthorization()

        // Wenn schon vorher erlaubt war, sofort starten (sonst kommt später der Auth-Callback)
        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    // =====================================================
    // MARK: - CLLocationManagerDelegate
    // =====================================================

    /// Wird aufgerufen, wenn sich die Location-Berechtigung ändert
    /// (z. B. durch Systemdialog oder Einstellungen).
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        // @Published-Properties sollten für SwiftUI auf dem Main-Thread geändert werden.
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            // Sicherheitshalber konfigurieren wir Background-Flags erneut,
            // falls iOS den Manager intern neu initialisiert/ändert.
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false

            // Startet kontinuierliche Standortupdates.
            manager.startUpdatingLocation()

        case .denied, .restricted:
            // Nutzer hat abgelehnt oder das System verbietet Location (z.B. Screen Time/MDM).
            // Dann stoppen wir Updates, um Akku zu sparen und unnötige Calls zu vermeiden.
            manager.stopUpdatingLocation()

        case .notDetermined:
            // User hat noch nicht entschieden -> nichts erzwingen.
            break

        @unknown default:
            // Zukunftssicher: bei neuen Statuswerten lieber vorsichtig sein.
            break
        }
    }

    /// Wird aufgerufen, wenn neue Standortdaten verfügbar sind.
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        // iOS liefert ggf. mehrere Locations (Batch).
        // Wir nehmen die letzte (= aktuellste) Position.
        guard let loc = locations.last else { return }

        // letzte Position veröffentlichen (z.B. für UI/Debug)
        DispatchQueue.main.async {
            self.lastLocation = loc
            self.lastLocationError = nil
        }

        // Weiterreichen an BluetoothManager:
        // - zählt Distanz
        // - schreibt (im Lite-Modus) Geolocation-Events in die BIN-Datei
        bluetoothManager?.handleLocationUpdate(loc)
    }

    /// Letzte GPS-Fehlermeldung (für UI-Anzeige)
    @Published var lastLocationError: String?

    /// Fehler-Callback vom CoreLocation-Manager (z.B. kein GPS, Timeout, denied).
    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        print("LocationManager error: \(error)")
        DispatchQueue.main.async {
            self.lastLocationError = error.localizedDescription
        }
    }
}
