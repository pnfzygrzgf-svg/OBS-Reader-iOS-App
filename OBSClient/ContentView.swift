import SwiftUI
import UIKit

/// Hauptbildschirm der App:
/// - Verbindungsstatus (Bluetooth / Standort)
/// - Live-Messwerte (Abstände, Überholabstand)
/// - Lenkerbreite-Einstellung
/// - Record-Button & gespeicherte Aufnahme-Info
struct ContentView: View {
    /// Zentraler Bluetooth-/Recording-Status aus dem BluetoothManager
    @EnvironmentObject var bt: BluetoothManager

    /// Steuert, ob nach dem Stoppen der Aufnahme kurz ein Toast angezeigt wird
    @State private var showSaveConfirmation = false
    
    /// Steuert, ob die Distanz links/rechts in der Messkarten-Ansicht angezeigt wird
    @State private var showSideDistances = false   // steuert Anzeige von Abstand links/rechts

    var body: some View {
        NavigationStack {
            ZStack {
                // Hintergrund (wie Einstellungen-App)
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                // Inhalt
                ScrollView(.vertical) {
                    VStack(spacing: 24) {
                        LogoView()

                        // NEU: Gerätetyp-Auswahl
                        DeviceTypeSelectionCard()

                        ConnectionStatusCard()

                        // Hinweise für Bluetooth-Status / -rechte
                        if !bt.isPoweredOn || !bt.hasBluetoothPermission {
                            BluetoothPermissionHintView()
                        }

                        // Karte mit Sensorwerten und Überholabstand
                        MeasurementsCardView(showSideDistances: $showSideDistances)

                        // Lenkerbreite-Einstellung
                        HandlebarWidthView(handlebarWidthCm: $bt.handlebarWidthCm)

                        // Hinweis zu Standortrechten (inkl. „Immer erlauben“),
                        // jetzt direkt unter der Lenkerbreite
                        if !bt.isLocationEnabled || !bt.hasLocationAlwaysPermission {
                            LocationPermissionHintView()
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 80) // Platz für Record-Button
                    .font(.obsBody)
                }
                .scrollIndicators(.hidden)

                // Kurze Bestätigung nach "Aufnahme stoppen"
                if showSaveConfirmation {
                    SaveConfirmationToast(
                        overtakeCount: bt.currentOvertakeCount,
                        distanceText: formattedDistanceKm(fromMeters: bt.currentDistanceMeters)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("OBS Recorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Navigation zur Info-Seite
                    NavigationLink {
                        InfoView()
                    } label: {
                        Image(systemName: "info.circle")
                    }

                    // WICHTIG:
                    // Der frühere Ordner-Button, der DataExportView geöffnet hat,
                    // ist entfernt – DataExportView hängt jetzt unter dem Portal-Tab.
                }
            }
            // Fester Record-Button am unteren Rand (kleiner „Floating Button“)
            .safeAreaInset(edge: .bottom) {
                RecordButtonView(
                    isConnected: bt.isConnected,
                    isRecording: bt.isRecording,
                    onTap: handleRecordTap
                )
            }
        }
    }

    // MARK: - Actions

    /// Startet/stoppt die Aufnahme, inkl. Haptik & kleiner Animation.
    private func handleRecordTap() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if bt.isRecording {
                bt.stopRecording()

                // Bestätigung + Statistik anzeigen
                showSaveConfirmation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        showSaveConfirmation = false
                    }
                }
            } else {
                bt.startRecording()
            }
        }

        // „Success“-Feedback nach Tap
        generator.notificationOccurred(.success)
    }

    // MARK: - Hilfsfunktionen

    /// Formatiert eine Distanz in Metern als String in Kilometern mit 2 Nachkommastellen.
    private func formattedDistanceKm(fromMeters meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.2f", km)
    }
}

// MARK: - Logo

/// Logo-Zeile oben im Screen
struct LogoView: View {
    var body: some View {
        Image("OBSLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 64, height: 64)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Device Type Selection

/// Karte, mit der der Nutzer zwischen OBS Lite und OBS Classic wählen kann.
struct DeviceTypeSelectionCard: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gerätetyp")
                .font(.obsSectionTitle)

            Picker("Gerätetyp", selection: $bt.deviceType) {
                ForEach(ObsDeviceType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Text(bt.deviceType.description)
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .obsCardStyle()
    }
}

// MARK: - Connection Status (BLE)

/// Karte, die den Bluetooth-Verbindungsstatus zum OBS anzeigt.
struct ConnectionStatusCard: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .symbolVariant(.fill)
                .foregroundStyle(statusColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsSectionTitle)

                Text(subtitle)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .obsCardStyle()
    }

    /// Haupttitel abhängig vom Status
    private var title: String {
        if bt.isConnected {
            return "Mit OBS verbunden"
        }
        if !bt.isPoweredOn {
            return "Bluetooth deaktiviert"
        }
        if !bt.hasBluetoothPermission {
            return "Bluetooth-Zugriff erforderlich"
        }
        return "Nicht verbunden"
    }

    /// Untertitel mit konkreter Handlungsempfehlung
    private var subtitle: String {
        if bt.isConnected {
            return "Das Gerät sendet Messwerte."
        }
        if !bt.isPoweredOn {
            return "Aktiviere Bluetooth, um den Sensor zu verbinden."
        }
        if !bt.hasBluetoothPermission {
            return "Erlaube Bluetooth-Zugriff in den iOS-Einstellungen."
        }
        return "Warten auf Sensorverbindung."
    }

    /// Ampel-Farbe: grün = verbunden, rot = Problem, orange = suchend
    private var statusColor: Color {
        if bt.isConnected {
            return .green
        }
        if !bt.isPoweredOn || !bt.hasBluetoothPermission {
            return .red
        }
        return .orange
    }
}

// MARK: - Permission Hints

/// Hinweiskarte, falls Standortdienste / -berechtigungen nicht passen.
struct LocationPermissionHintView: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.fill")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.obsSectionTitle)

                Text(message)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)

                Button {
                    // Direkt zu den App-Einstellungen springen
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Einstellungen öffnen")
                        .font(.obsFootnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }

            Spacer()
        }
        .obsCardStyle()
    }

    /// Überschrift abhängig davon, ob GPS global oder nur für die App aus ist
    private var title: String {
        if !bt.isLocationEnabled {
            return "Standortdienste deaktiviert"
        }
        if !bt.hasLocationAlwaysPermission {
            return "Hintergrund-Standort deaktiviert"
        }
        return "Standortzugriff erforderlich"
    }

    /// Erklärung, warum GPS benötigt wird
    private var message: String {
        if !bt.isLocationEnabled {
            return """
Damit deine Fahrten vollständig aufgezeichnet werden können, müssen die Standortdienste (GPS) auf deinem Gerät aktiviert sein.
Aktiviere sie in den iOS-Einstellungen unter „Datenschutz & Sicherheit > Ortungsdienste“.
"""
        }

        // Fall: Standortdienste an, aber nur „Beim Verwenden erlaubt“
        return """
Damit deine Fahrten auch bei ausgeschaltetem Bildschirm und im Hintergrund aufgezeichnet werden können, braucht diese App „Immer“ Zugriff auf deinen Standort.

Tippe unten auf „Einstellungen öffnen“ und stelle unter
„Ortungsdienste > OBS Recorder > Zugriff auf Standort“
die Option auf „Immer“.
"""
    }
}

/// Hinweiskarte für Bluetooth-Einstellungen/Berechtigungen.
struct BluetoothPermissionHintView: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.obsSectionTitle)

                Text(message)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Einstellungen öffnen")
                        .font(.obsFootnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }

            Spacer()
        }
        .obsCardStyle()
    }

    private var title: String {
        if !bt.isPoweredOn {
            return "Bluetooth deaktiviert"
        }
        return "Bluetooth-Zugriff erforderlich"
    }

    private var message: String {
        if !bt.isPoweredOn {
            return "Aktiviere Bluetooth in den Systemeinstellungen, damit sich dein OBS-Gerät verbinden und Messwerte senden kann."
        }
        return "Damit sich dein OBS-Gerät verbinden kann, benötigt diese App Zugriff auf Bluetooth. Erlaube den Zugriff in den iOS-Einstellungen."
    }
}

// MARK: - Measurements Card

/// Karte mit den aktuellen Sensorwerten:
/// - optional Seitenabstände links/rechts
/// - Überholabstand (immer sichtbar)
struct MeasurementsCardView: View {
    @EnvironmentObject var bt: BluetoothManager
    @Binding var showSideDistances: Bool      // steuert Anzeige Seitenabstände

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sensorwerte")
                    .font(.obsSectionTitle)

                Spacer()

                // Schalter, ob „Abstand links/rechts“ überhaupt angezeigt werden soll
                Toggle("Abstände anzeigen", isOn: $showSideDistances)
                    .labelsHidden()
            }

            // Placeholder-Skelett anzeigen, solange keine Verbindung besteht
            // (nur wenn Seitenabstände aktiv sind)
            if !bt.isConnected && showSideDistances {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)
                }
                .redacted(reason: .placeholder)
            }

            // Bereich „Abstand links/rechts“ komplett ein-/ausblenden
            if showSideDistances {
                HStack(alignment: .top, spacing: 32) {
                    SensorValueView(
                        title: "Abstand links",
                        corrected: bt.leftCorrectedCm,
                        raw: bt.leftRawCm
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SensorValueView(
                        title: "Abstand rechts",
                        corrected: bt.rightCorrectedCm,
                        raw: bt.rightRawCm
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Überholabstand bleibt immer sichtbar
            OvertakeDistanceView(distance: bt.overtakeDistanceCm)
        }
        .obsCardStyle()
    }
}

// Einzelner Sensorblock mit Balken-Visualisierung & Info-Icons
struct SensorValueView: View {
    let title: String
    let corrected: Int?
    let raw: Int?

    @State private var showMeasuredInfo = false
    @State private var showCalculatedInfo = false

    /// Obergrenze für ProgressView-Skala (200 cm)
    private let maxDistance = 200.0 // 200 cm Skala

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.obsSectionTitle)

            // Berechneter Wert
            if let corrected {
                VStack(alignment: .leading, spacing: 6) {
                    // Wert in cm prominent anzeigen
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(corrected)")
                            .font(.obsValue)
                            .monospacedDigit()
                        Text("cm")
                            .font(.obsBody)
                            .foregroundStyle(.secondary)
                    }

                    // Balkenanzeige mit Farbcodierung je nach Abstand
                    ProgressView(
                        value: min(Double(corrected), maxDistance),
                        total: maxDistance
                    )
                    .tint(Color.overtakeColor(for: corrected))

                    // Label + Info-Icon für „Berechnet“
                    HStack(spacing: 4) {
                        Text("Berechnet")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)

                        Button {
                            showCalculatedInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .alert("Berechneter Abstand", isPresented: $showCalculatedInfo) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("„Berechnet“ berücksichtigt die Lenkerbreite: gemessener Abstand minus halbe Lenkerbreite.")
                    }
                }
            } else {
                Text("Noch kein berechneter Wert.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }

            // Rohwert
            if let raw {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Gemessen (Rohwert)")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)

                        Button {
                            showMeasuredInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 4) {
                        Text("\(raw)")
                            .font(.obsFootnote)
                            .monospacedDigit()
                        Text("cm")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .alert("Gemessener Rohwert", isPresented: $showMeasuredInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("„Gemessen (Rohwert)“ ist der Abstand, den der Sensor erfasst – ohne Korrektur um die Lenkerbreite.")
                }
            } else {
                Text("Noch kein Rohwert gemessen.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}


// Überholabstand mit Farbcodierung (grün/orange/rot)
struct OvertakeDistanceView: View {
    let distance: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Überholabstand")
                .font(.obsScreenTitle)

            if let distance {
                HStack(spacing: 8) {
                    // Farbkodierter Indikator (Ampelkreis)
                    Circle()
                        .fill(Color.overtakeColor(for: distance))
                        .frame(width: 12, height: 12)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(distance)")
                            .font(.obsValue)
                            .monospacedDigit()
                        Text("cm")
                            .font(.obsBody)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Noch kein Überholabstand berechnet.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Lenkerbreite

/// Card zum Einstellen der Lenkerbreite in cm.
/// Wird zur Berechnung des „berechneten“ Überholabstands verwendet.
struct HandlebarWidthView: View {
    @Binding var handlebarWidthCm: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lenkerbreite")
                .font(.obsSectionTitle)

            HStack {
                Text("\(handlebarWidthCm)")
                    .monospacedDigit()
                    .font(.obsBody)

                Text("cm")
                    .font(.obsBody)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Stepper zum Anpassen der Lenkerbreite (30–120 cm)
            Stepper(
                value: $handlebarWidthCm,
                in: 30...120,
                step: 1
            ) {
                EmptyView()
            }
            .labelsHidden()

            Text("Wird zur Berechnung des Überholabstands verwendet.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
        .obsCardStyle()
    }
}

// MARK: - Record Button

/// Großer Button am unteren Rand zum Starten/Stoppen der Aufnahme.
struct RecordButtonView: View {
    let isConnected: Bool
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
                        .font(.obsSectionTitle)
                        .fontWeight(.semibold)

                    if !isConnected {
                        Text("Sensor nicht verbunden")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: isRecording
                        ? [Color.red.opacity(0.9), Color.red]
                        : [Color.green.opacity(0.9), Color.green],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: isConnected ? 4 : 0)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .scaleEffect(isRecording ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isRecording)
        }
        // Button nur anklickbar, wenn Sensor verbunden ist
        .disabled(!isConnected)
        .opacity(isConnected ? 1.0 : 0.5)
    }
}

// MARK: - Save Confirmation Toast

/// Kleiner Toast, der nach dem Stoppen der Aufnahme kurz die
/// Anzahl der Überholvorgänge und die Fahrstrecke anzeigt.
struct SaveConfirmationToast: View {
    let overtakeCount: Int
    let distanceText: String

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 4) {
                Text("Aufnahme gespeichert.")
                    .font(.obsFootnote.weight(.semibold))

                Text("\(overtakeCount) Überholvorgänge · \(distanceText) km")
                    .font(.obsFootnote)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(radius: 4)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Styling & Helpers

/// Card-Style-Erweiterung für wiederverwendbare Kartenoptik.
extension View {
    func obsCardStyle() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }
}

/// Ampel-Farbskala für Abstände (rot/orange/grün).
extension Color {
    static func overtakeColor(for distance: Int) -> Color {
        switch distance {
        case ..<100:
            return .red               // bis 1 m
        case 100..<150:
            return .orange            // 1 m bis 1.5 m
        default:
            return .green             // > 1.5 m
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(BluetoothManager())
}
