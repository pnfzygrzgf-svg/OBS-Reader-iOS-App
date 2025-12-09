import SwiftUI

/// Einstiegspunkt der App (SwiftUI-App-Lifecycle).
/// Jetzt mit TabView:
/// - Tab 1: deine bisherige OBS-App (ContentView)
/// - Tab 2: Portal-Integration (PortalTracksListView)
@main
struct OBSClientApp: App {
    @StateObject private var bluetoothManager: BluetoothManager
    @StateObject private var locationManager: LocationManager

    @State private var showSplash = true

    init() {
        let bt = BluetoothManager()
        _bluetoothManager = StateObject(wrappedValue: bt)
        _locationManager = StateObject(wrappedValue: LocationManager(bluetoothManager: bt))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView {
                    // Tab 1: deine bestehende App
                    NavigationStack {
                        ContentView()
                            .environmentObject(bluetoothManager)
                        // falls du den LocationManager im UI brauchst:
                        // .environmentObject(locationManager)
                    }
                    .tabItem {
                        Label("Sensor", systemImage: "dot.radiowaves.left.and.right")
                    }

                    // Tab 2: Portal-Integration
                    NavigationStack {
                        PortalTracksListView()
                    }
                    .tabItem {
                        Label("Portal", systemImage: "map")
                    }
                }

                // Splash oben drüber
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
