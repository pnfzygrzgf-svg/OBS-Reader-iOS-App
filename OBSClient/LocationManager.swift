import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastLocation: CLLocation?

    private let manager: CLLocationManager
    private unowned let bluetoothManager: BluetoothManager

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager

        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus

        super.init()

        manager.delegate = self

        // GPS möglichst ähnlich zu Android:
        // - hohe Genauigkeit
        // - möglichst viele Updates
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone  // KEIN Mindestabstand, jedes Update mitnehmen

        // Berechtigung anfragen
        manager.requestWhenInUseAuthorization()

        // Falls schon erlaubt war, direkt starten
        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocation = loc
        }

        // Hier werden die Geolocation-Events erzeugt und in die BIN geschrieben
        bluetoothManager.handleLocationUpdate(loc)
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        print("LocationManager error: \(error)")
    }
}

