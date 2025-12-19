import SwiftUI

/// Einstiegspunkt der App (SwiftUI-App-Lifecycle).
///
/// Aufgaben dieser Datei:
/// - Erstellt die zentralen „Singleton“-StateObjects (Bluetooth + Location)
/// - Stellt sie bei Bedarf per `environmentObject` den Views zur Verfügung
/// - Baut die Tab-Navigation (Sensor / Aufzeichnungen)
/// - Zeigt optional einen Splash-Screen am Start
@main
struct OBSClientApp: App {

    // =====================================================
    // MARK: - Globaler App-State
    // =====================================================

    /// Zentrale Instanz für BLE (Scan, Connect, Recording, Sensorwerte).
    /// `@StateObject` sorgt dafür, dass die Instanz über die Lebensdauer der App-UI bestehen bleibt.
    @StateObject private var bluetoothManager: BluetoothManager

    /// Zentrale Instanz für Standort (Permissions + GPS-Updates).
    /// Wird hier erstellt, damit sie früh existiert und ggf. direkt Updates liefern kann.
    @StateObject private var locationManager: LocationManager

    /// Steuert, ob der Splash-Screen noch angezeigt werden soll.
    @State private var showSplash = true

    // =====================================================
    // MARK: - Init
    // =====================================================

    /// App-Init läuft einmal beim Start.
    ///
    /// Wichtig: Wir erstellen `BluetoothManager` und `LocationManager` hier manuell,
    /// damit beide dieselbe BluetoothManager-Instanz verwenden und
    /// LocationManager seine GPS-Updates direkt dorthin leiten kann.
    init() {
        let bt = BluetoothManager()

        // StateObject muss über _variable initialisiert werden, wenn wir es im init setzen.
        _bluetoothManager = StateObject(wrappedValue: bt)

        // LocationManager braucht bt als Dependency, damit er `handleLocationUpdate` aufrufen kann.
        _locationManager = StateObject(wrappedValue: LocationManager(bluetoothManager: bt))
    }

    // =====================================================
    // MARK: - UI Root
    // =====================================================

    var body: some Scene {
        WindowGroup {
            ZStack {
                // TabView ist die Hauptnavigation der App.
                TabView {

                    // -------------------------------------------------
                    // Tab 1: Sensor / Hauptansicht
                    // -------------------------------------------------
                    ContentView()
                        // BluetoothManager als EnvironmentObject,
                        // damit ContentView und Unterviews automatisch Zugriff haben.
                        .environmentObject(bluetoothManager)

                        // Optional: LocationManager ebenfalls in die UI hängen,
                        // falls du z.B. Debug/Status anzeigen willst.
                        // .environmentObject(locationManager)

                        .tabItem {
                            Label("Sensor", systemImage: "dot.radiowaves.left.and.right")
                        }

                    // -------------------------------------------------
                    // Tab 2: Portal / Aufzeichnungen
                    // -------------------------------------------------
                    // NavigationStack: erlaubt Push-Navigation innerhalb dieses Tabs.
                    NavigationStack {
                        PortalHomeView()
                    }
                    .tabItem {
                        Label("Aufzeichnungen", systemImage: "tray.full")
                    }
                }

                // -------------------------------------------------
                // Splash-Screen (liegt über Tabs)
                // -------------------------------------------------
                if showSplash {
                    SplashView()
                        // Fade in/out
                        .transition(.opacity)
                        // Sicherstellen, dass Splash über allem liegt.
                        .zIndex(1)
                }
            }
            .onAppear {
                // Beim Start: Splash für 2 Sekunden anzeigen,
                // dann mit Animation ausblenden.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
