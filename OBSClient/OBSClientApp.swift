import SwiftUI

@main
struct OBSClientApp: App {
    // 1) Unsere zentralen Objekte, die die ganze App über leben sollen
    @StateObject private var bluetoothManager: BluetoothManager
    @StateObject private var locationManager: LocationManager

    init() {
        // 2) Erst den BluetoothManager erzeugen
        let bt = BluetoothManager()
        _bluetoothManager = StateObject(wrappedValue: bt)

        // 3) Dann den LocationManager, der den bt kennt
        _locationManager = StateObject(wrappedValue: LocationManager(bluetoothManager: bt))
    }

    var body: some Scene {
        WindowGroup {
            // 4) ContentView bekommt den BluetoothManager als Environment Object
            ContentView()
                .environmentObject(bluetoothManager)
            // locationManager muss nicht ins Environment,
            // es reicht, dass er existiert und im Hintergrund GPS-Updates an bt schickt.
        }
    }
}
