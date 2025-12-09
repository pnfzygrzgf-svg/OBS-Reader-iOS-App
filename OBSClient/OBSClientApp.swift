// OBSClientApp.swift

import SwiftUI

/// Einstiegspunkt der App (SwiftUI-App-Lifecycle).
/// Hier werden die zentralen StateObjects erstellt und der Splash-Screen gesteuert.
@main
struct OBSClientApp: App {
    // Deine bisherigen StateObjects bleiben wie sie sind:
    // - BluetoothManager verwaltet BLE-Verbindung, Recording, etc.
    // - LocationManager kümmert sich um GPS/Permissions (vermutlich dein eigener Wrapper).
    @StateObject private var bluetoothManager: BluetoothManager
    @StateObject private var locationManager: LocationManager

    /// Steuert, ob der Splash-Screen sichtbar ist.
    /// Startet als `true` und wird nach einer kurzen Zeit auf `false` animiert.
    @State private var showSplash = true

    /// Custom-Init, um beide StateObjects gezielt zu verdrahten.
    ///
    /// Wichtig:
    /// - `BluetoothManager` wird einmal erzeugt.
    /// - Derselbe `BluetoothManager` wird an `LocationManager` übergeben,
    ///   falls der LocationManager z. B. GPS-Events an BluetoothManager weitergibt.
    init() {
        let bt = BluetoothManager()
        _bluetoothManager = StateObject(wrappedValue: bt)
        _locationManager = StateObject(wrappedValue: LocationManager(bluetoothManager: bt))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Die eigentliche App-UI.
                // ContentView bekommt den BluetoothManager als EnvironmentObject
                // und kann damit überall im View-Hierarchie darauf zugreifen.
                ContentView()
                    .environmentObject(bluetoothManager)
                // Falls LocationManager im UI benötigt wird, könntest du ihn hier
                // ebenfalls mit .environmentObject(locationManager) durchreichen.

                // SplashScreen liegt oben drüber, solange showSplash == true.
                // Durch die ZStack-Reihenfolge wird SplashView „über“ ContentView gerendert.
                if showSplash {
                    SplashView()
                        .transition(.opacity) // weiche Ein-/Ausblendung beim toggeln von showSplash
                        .zIndex(1)            // sicherstellen, dass SplashView vor ContentView liegt
                }
            }
            .onAppear {
                // Wird aufgerufen, wenn das Window/Root-View erscheint.
                // Hier steuern wir die Dauer des Splashscreens (hier: 2 Sekunden).
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // Splash ausblenden mit einer sanften Fade-Out-Animation
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
