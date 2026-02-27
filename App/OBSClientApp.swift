// SPDX-License-Identifier: GPL-3.0-or-later

// OBSClientApp.swift

import SwiftUI

@main
struct OBSClientApp: App {

    // =====================================================
    // MARK: - Globaler App-State
    // =====================================================

    @StateObject private var bluetoothManager: BluetoothManager
    @StateObject private var locationManager: LocationManager

    @State private var showSplash = true
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    // =====================================================
    // MARK: - Init
    // =====================================================

    init() {
        let bt = BluetoothManager()
        _bluetoothManager = StateObject(wrappedValue: bt)
        _locationManager = StateObject(wrappedValue: LocationManager(bluetoothManager: bt))
    }

    // =====================================================
    // MARK: - UI Root
    // =====================================================

    var body: some Scene {
        WindowGroup {
            ZStack {

                TabView {

                    // -------------------------------------------------
                    // Tab 1: Sensor / Hauptansicht
                    // -------------------------------------------------
                    ContentView()
                        .environmentObject(bluetoothManager)
                        .environmentObject(locationManager)
                        .tabItem {
                            Label("Sensor", systemImage: "dot.radiowaves.left.and.right")
                        }

                    // -------------------------------------------------
                    // Tab 2: Karte (Full-Screen + Tracking)
                    // -------------------------------------------------
                    NavigationStack { MapHomeView() }
                        .environmentObject(bluetoothManager)
                        .environmentObject(locationManager)

                    .tabItem {
                        Label("Karte", systemImage: "map")
                    }

                    // -------------------------------------------------
                    // Tab 3: Portal / Aufzeichnungen
                    // -------------------------------------------------
                    NavigationStack {
                        PortalHomeView()
                    }
                    .environmentObject(bluetoothManager)
                    .environmentObject(locationManager)
                    .tabItem {
                        Label("Aufzeichnungen", systemImage: "tray.full")
                    }
                }
                .tint(.obsAccentV2)

                // -------------------------------------------------
                // Splash-Screen (liegt über Tabs)
                // -------------------------------------------------
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }

                // -------------------------------------------------
                // Onboarding (liegt über allem)
                // -------------------------------------------------
                if !hasSeenOnboarding && !showSplash {
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            hasSeenOnboarding = true
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(OBSTiming.splashDuration))
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
            }
        }
    }
}

