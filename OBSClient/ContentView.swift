import SwiftUI
import UIKit

/// Haupt-UI der App.
/// Zeigt:
/// - Logo / Gerätetyp-Auswahl
/// - Verbindungsstatus + Permission-Hinweise
/// - Live-Sensorwerte + Lenkerbreite
/// - Record-Button (Start/Stop Aufnahme)
struct ContentView: View {
    /// Gemeinsamer BluetoothManager aus dem Environment (von App/Scene bereitgestellt).
    @EnvironmentObject var bt: BluetoothManager

    /// Steuert, ob nach dem Stoppen kurz ein „Gespeichert“-Toast angezeigt wird.
    @State private var showSaveConfirmation = false

    /// Toggle für die Anzeige der separaten Links/Rechts-Abstände.
    @State private var showSideDistances = false

    /// Cancelbarer Task für den Toast-Timer, damit sich Anzeigen sauber überschneiden/abbrechen lassen.
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                // Hintergrundfarbe wie in iOS Settings / Gruppen-Listen.
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                // Scrollbarer Inhalt (damit auf kleinen Geräten alles erreichbar bleibt).
                ScrollView(.vertical) {
                    VStack(spacing: 24) {
                        // App-Logo oben
                        LogoView()

                        // Segment-Picker: Lite vs Classic
                        DeviceTypeSelectionCard()

                        // Verbindung/Statusanzeige zum Sensor
                        ConnectionStatusCard()

                        // Hinweisbox, wenn Bluetooth aus oder keine Rechte vorhanden.
                        if !bt.isPoweredOn || !bt.hasBluetoothPermission {
                            BluetoothPermissionHintView()
                        }

                        // Sensorwerte/Überholabstand (inkl. Toggle für links/rechts)
                        MeasurementsCardView(showSideDistances: $showSideDistances)

                        // Lenkerbreite beeinflusst Korrektur/Überholabstand
                        HandlebarWidthView(handlebarWidthCm: $bt.handlebarWidthCm)

                        // Hinweisbox, wenn Standort nicht aktiv / kein „Immer“-Zugriff.
                        if !bt.isLocationEnabled || !bt.hasLocationAlwaysPermission {
                            LocationPermissionHintView()
                        }

                        // Kein Spacer nötig: ScrollView endet sauber über padding unten.
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 80) // Platz für den Record-Button, der unten „inset“ ist.
                    .font(.obsBody)       // Default-Font für die View-Hierarchie
                }
                // UI-Polish: keine Scroll-Indikatoren + Keyboard sofort weg beim Scrollen
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)

                // Overlay-Toast: wird eingeblendet, wenn eine Aufnahme gespeichert wurde.
                if showSaveConfirmation {
                    SaveConfirmationToast(
                        overtakeCount: bt.currentOvertakeCount,
                        distanceText: DistanceFormatter.kmString(fromMeters: bt.currentDistanceMeters)
                    )
                    // Animation beim Ein-/Ausblenden
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("OBS Recorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Toolbar: Info-Icon führt zu InfoView
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        InfoView()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            // Fixierter Bereich am unteren Rand: Record Button
            .safeAreaInset(edge: .bottom) {
                RecordButtonView(
                    isConnected: bt.isConnected,
                    isRecording: bt.isRecording,
                    onTap: handleRecordTap
                )
            }
            // Cleanup: falls View verschwindet, Toast-Task abbrechen
            .onDisappear {
                toastTask?.cancel()
                toastTask = nil
            }
        }
    }

    // MARK: - Actions

    /// Handler für den Record-Button.
    /// - Startet/Stoppt die Aufnahme im BluetoothManager
    /// - zeigt beim Stoppen kurz einen Toast „Aufnahme gespeichert“
    /// - haptisches Feedback (success/warning)
    @MainActor
    private func handleRecordTap() {
        // Schutz: Aufnahme nur möglich, wenn verbunden.
        guard bt.isConnected else {
            Haptics.shared.warning()
            return
        }

        // UI-Animation für Zustandswechsel (Start/Stop)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if bt.isRecording {
                // Stop: Datei schließen + Toast anzeigen
                bt.stopRecording()
                showSaveToastForTwoSeconds()
            } else {
                // Start: neue Session beginnen
                bt.startRecording()
            }
        }

        Haptics.shared.success()
    }

    /// Zeigt den „Gespeichert“-Toast für 2 Sekunden.
    /// Wird über eine Task realisiert, die cancelbar ist (z.B. bei erneutem Stop).
    private func showSaveToastForTwoSeconds() {
        // Falls ein alter Toast-Timer läuft: abbrechen
        toastTask?.cancel()

        // Toast sichtbar schalten
        showSaveConfirmation = true

        // Neue Task: 2s warten, dann Toast ausblenden (auf MainActor)
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { showSaveConfirmation = false }
            }
        }
    }
}

// MARK: - Logo

/// Zeigt das App-/Projektlogo oben mittig.
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

/// Karte für die Auswahl des Gerätetyps (Lite/Classic).
/// Setzt direkt `bt.deviceType`, was im BluetoothManager den Scan neu startet.
struct DeviceTypeSelectionCard: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gerätetyp")
                .font(.obsSectionTitle)

            // Segment-Picker: schaltet zwischen Lite/Classic um
            Picker("Gerätetyp", selection: $bt.deviceType) {
                ForEach(ObsDeviceType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Kurzbeschreibung, was der ausgewählte Modus bedeutet
            Text(bt.deviceType.description)
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .obsCardStyle()
    }
}

// MARK: - Connection Status (Presentation Model)

/// Presentation Model:
/// Wandelt BluetoothManager-Status in UI-Strings + Farbe um,
/// damit die View selbst schlank bleibt.
struct ConnectionStatusPresentation {
    let title: String
    let subtitle: String
    let color: Color

    /// Erzeugt den darstellbaren Status aus dem BluetoothManager.
    init(bt: BluetoothManager) {
        if bt.isConnected {
            title = "Mit OBS verbunden"
            color = .green

            // nil-safety: falls Infos noch nicht gelesen wurden
            let detected = bt.detectedDeviceType?.displayName ?? "unbekannt"
            let mfg = bt.manufacturerName.nonEmptyOrDash
            let fw  = bt.firmwareRevision.nonEmptyOrDash

            // Mehrzeiliger Debug/Info-Text
            subtitle = """
            Name: \(bt.connectedName)
            LocalName: \(bt.connectedLocalName)
            Detected: \(detected) · Quelle: \(bt.lastBleSource)
            Hersteller: \(mfg) · Firmware: \(fw)
            ID: \(bt.connectedId)
            """
            return
        }

        // Nicht verbunden: genauer Grund anzeigen
        if !bt.isPoweredOn {
            title = "Bluetooth deaktiviert"
            subtitle = "Aktiviere Bluetooth, um den Sensor zu verbinden."
            color = .red
            return
        }

        if !bt.hasBluetoothPermission {
            title = "Bluetooth-Zugriff erforderlich"
            subtitle = "Erlaube Bluetooth-Zugriff in den iOS-Einstellungen."
            color = .red
            return
        }

        // Standardfall: Bluetooth an, Rechte ok, aber noch keine Verbindung
        title = "Nicht verbunden"
        subtitle = "Warten auf Sensorverbindung."
        color = .orange
    }
}

/// Visuelle Karte für den Connection Status.
/// Nutzt ConnectionStatusPresentation, um UI konsistent zu halten.
struct ConnectionStatusCard: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        let p = ConnectionStatusPresentation(bt: bt)

        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .symbolVariant(.fill)
                .foregroundStyle(p.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(p.title)
                    .font(.obsSectionTitle)

                Text(p.subtitle)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .obsCardStyle()
    }
}

// MARK: - Permission Hints

/// Hinweis-Karte für Location Permissions.
/// Zeigt je nach Zustand unterschiedliche Texte und bietet einen Button in die iOS Settings.
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

                // Öffnet direkt die App-Einstellungen
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

    /// Titel abhängig davon, ob Location Services aus sind oder „Immer“ fehlt.
    private var title: String {
        if !bt.isLocationEnabled { return "Standortdienste deaktiviert" }
        if !bt.hasLocationAlwaysPermission { return "Hintergrund-Standort deaktiviert" }
        return "Standortzugriff erforderlich"
    }

    /// Erklärungstext für den Benutzer (mit konkreter iOS-Navigation).
    private var message: String {
        if !bt.isLocationEnabled {
            return """
Damit deine Fahrten vollständig aufgezeichnet werden können, müssen die Standortdienste (GPS) aktiviert sein.
Aktiviere sie in den iOS-Einstellungen unter „Datenschutz & Sicherheit > Ortungsdienste“.
"""
        }

        return """
Damit deine Fahrten auch bei ausgeschaltetem Bildschirm und im Hintergrund aufgezeichnet werden können, braucht diese App „Immer“ Zugriff auf deinen Standort.

Tippe unten auf „Einstellungen öffnen“ und stelle unter
„Ortungsdienste > OBS Recorder > Zugriff auf Standort“
die Option auf „Immer“.
"""
    }
}

/// Hinweis-Karte für Bluetooth (aus / keine Berechtigung).
/// Bietet ebenfalls einen Shortcut in die iOS Settings.
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

    /// Titel unterscheidet: Bluetooth aus vs. Permission fehlt.
    private var title: String {
        bt.isPoweredOn ? "Bluetooth-Zugriff erforderlich" : "Bluetooth deaktiviert"
    }

    /// Beschreibung, was der User tun soll.
    private var message: String {
        if !bt.isPoweredOn {
            return "Aktiviere Bluetooth in den Systemeinstellungen, damit sich dein OBS-Gerät verbinden und Messwerte senden kann."
        }
        return "Damit sich dein OBS-Gerät verbinden kann, benötigt diese App Zugriff auf Bluetooth. Erlaube den Zugriff in den iOS-Einstellungen."
    }
}

// MARK: - Measurements Card

/// Karte für die Anzeige der Sensorwerte.
/// Enthält:
/// - Toggle „Abstände anzeigen“ (links/rechts)
/// - Optional Skeleton solange keine Werte da sind
/// - Überholabstand (Median beim Button-Press)
struct MeasurementsCardView: View {
    @EnvironmentObject var bt: BluetoothManager
    @Binding var showSideDistances: Bool

    /// true, wenn die UI links/rechts anzeigen soll, aber noch keine Werte angekommen sind.
    private var isWaitingForSideValues: Bool {
        showSideDistances
        && bt.isConnected
        && bt.leftRawCm == nil
        && bt.rightRawCm == nil
        && bt.leftCorrectedCm == nil
        && bt.rightCorrectedCm == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sensorwerte")
                    .font(.obsSectionTitle)

                Spacer()

                // Toggle versteckt Label visuell, aber mit Accessibility Label versehen
                Toggle("Abstände anzeigen", isOn: $showSideDistances)
                    .labelsHidden()
                    .accessibilityLabel("Abstände links und rechts anzeigen")
            }

            // Skeleton: wenn nicht verbunden ODER verbunden aber noch keine Werte
            if showSideDistances && (!bt.isConnected || isWaitingForSideValues) {
                SensorValuesSkeletonView()
                    .transition(.opacity)
            }

            // Links/Rechts nur anzeigen, wenn Toggle aktiv
            if showSideDistances {
                HStack(alignment: .top, spacing: 32) {
                    SensorValueView(
                        title: "Abstand links",
                        corrected: bt.leftCorrectedCm,
                        raw: bt.leftRawCm
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Redaction: zeigt Placeholder-Look, wenn wir auf Werte warten
                    .redacted(reason: isWaitingForSideValues ? .placeholder : [])

                    SensorValueView(
                        title: "Abstand rechts",
                        corrected: bt.rightCorrectedCm,
                        raw: bt.rightRawCm
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .redacted(reason: isWaitingForSideValues ? .placeholder : [])
                }
            }

            // Überholabstand (Median) immer anzeigen
            OvertakeDistanceView(distance: bt.overtakeDistanceCm)
        }
        .obsCardStyle()
    }
}

/// Kleine Skeleton-View als Platzhalter (optischer Ladeschimmer via redacted).
private struct SensorValuesSkeletonView: View {
    var body: some View {
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
}

// MARK: - Sensor Value Views

/// Darstellung eines einzelnen Sensorwerts (links oder rechts).
/// Zeigt:
/// - korrigierten Wert (unter Berücksichtigung Lenkerbreite)
/// - optional Rohwert
/// - kleine Info-Alerts, die den Unterschied erklären
struct SensorValueView: View {
    let title: String
    let corrected: Int?
    let raw: Int?

    @State private var showMeasuredInfo = false
    @State private var showCalculatedInfo = false

    /// Obergrenze für ProgressView (rein UI-Design, keine Validierung).
    private let maxDistance = 200.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.obsSectionTitle)

            // --- Korrigierter Wert (berechnet) ---
            if let corrected {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(corrected)")
                            .font(.obsValue)
                            .monospacedDigit()
                        Text("cm")
                            .font(.obsBody)
                            .foregroundStyle(.secondary)
                    }

                    // Visualisierung des Abstands als Balken
                    ProgressView(
                        value: min(Double(corrected), maxDistance),
                        total: maxDistance
                    )
                    // Farbgebung abhängig von Abstand (z.B. rot/gelb/grün)
                    .tint(Color.overtakeColor(for: corrected))

                    // Label + Info-Button (Alert)
                    HStack(spacing: 4) {
                        Text("Berechnet")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)

                        Button { showCalculatedInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Info: Berechneter Abstand")
                    }
                    .alert("Berechneter Abstand", isPresented: $showCalculatedInfo) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("„Berechnet“ berücksichtigt die Lenkerbreite: gemessener Abstand minus halbe Lenkerbreite.")
                    }
                }
            } else {
                // Falls noch kein korrigierter Wert vorhanden
                Text("Noch kein berechneter Wert.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }

            // --- Rohwert (gemessen) ---
            if let raw {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Gemessen (Rohwert)")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)

                        Button { showMeasuredInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Info: Gemessener Rohwert")
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
                // Falls noch kein Rohwert vorhanden
                Text("Noch kein Rohwert gemessen.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Zeigt den „Überholabstand“ (Median beim Button-Press).
/// Nutzt eine farbige Ampel (über Color.overtakeColor(for:)).
struct OvertakeDistanceView: View {
    let distance: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Überholabstand")
                .font(.obsScreenTitle)

            if let distance {
                HStack(spacing: 8) {
                    // Farbindikator für die Bewertung des Abstands
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
                    .accessibilityValue("\(distance) Zentimeter")
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

/// Einstellkarte für die Lenkerbreite.
/// Diese Breite wird zur Korrektur der Messwerte verwendet:
/// berechnet = gemessen - (Lenkerbreite / 2)
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

            // Stepper: erlaubt komfortables Einstellen in 1cm Schritten
            Stepper(value: $handlebarWidthCm, in: 30...120, step: 1) {
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

/// Großer Button am unteren Rand.
/// - disabled, wenn nicht verbunden
/// - wechselt Icon/Text je nach Recording-Status
/// - ruft onTap() auf (ContentView steuert dann bt.start/stopRecording)
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

                    // Zusatzhinweis, wenn Sensor nicht verbunden
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
            // Farbverlauf je nach Zustand: Grün = Start, Rot = Stop
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
        // Wenn nicht verbunden: Button deaktivieren und optisch „ausgrauen“
        .disabled(!isConnected)
        .opacity(isConnected ? 1.0 : 0.5)
    }
}

// MARK: - Save Confirmation Toast

/// Kleiner „Toast“ am unteren Rand als Feedback nach dem Speichern.
/// Zeigt:
/// - „Aufnahme gespeichert.“
/// - Anzahl Überholvorgänge + Distanz (km)
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
            // iOS Material-Background für „Toast“-Look
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(radius: 4)
            // Abstand über dem Record-Button
            .padding(.bottom, 120)
        }
    }
}
