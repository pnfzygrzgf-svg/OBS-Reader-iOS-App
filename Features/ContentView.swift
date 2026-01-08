// ContentView.swift

import SwiftUI
import UIKit
import Combine

/// Haupt-UI der App.
/// Zeigt:
/// - Logo
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

    /// Cancelbarer Task für den Toast-Timer.
    @State private var toastTask: Task<Void, Never>?

    /// Steuert, ob die Info-Ansicht als Sheet angezeigt wird.
    @State private var showingInfo = false

    // MARK: - Connection Watchdog (UI-seitig)
    /// Zeitpunkt der letzten eingehenden Sensordaten (aus Sicht der UI).
    @State private var lastSensorUpdate: Date = .distantPast

    /// UI-Flag: Verbindung wirkt "stale" (keine Daten mehr), auch wenn bt.isConnected ggf. noch true ist.
    @State private var connectionIsStale = false

    /// Wie lange ohne Daten, bis wir die Verbindung als verloren darstellen.
    private let staleAfterSeconds: TimeInterval = 3.5

    private var isConnectedForUI: Bool {
        bt.isConnected && !connectionIsStale
    }

    private let watchdogTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    // MARK: - Disconnect Notice Alert
    @State private var showDisconnectAlert = false
    @State private var disconnectAlertText = ""

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(spacing: 24) {
                    LogoView {
                        showingInfo = true
                    }

                    ConnectionStatusCard(isConnectionStale: connectionIsStale)

                    if !bt.isPoweredOn || !bt.hasBluetoothPermission {
                        BluetoothPermissionHintView()
                    }

                    MeasurementsCardView(
                        showSideDistances: $showSideDistances,
                        isConnectedForUI: isConnectedForUI
                    )

                    HandlebarWidthView(handlebarWidthCm: $bt.handlebarWidthCm)

                    if !bt.isLocationEnabled || !bt.hasLocationAlwaysPermission {
                        LocationPermissionHintView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 80)
                .font(.obsBody)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)

            if showSaveConfirmation {
                SaveConfirmationToast(
                    overtakeCount: bt.currentOvertakeCount,
                    distanceText: OBSDistanceFormatterV2.kmString(fromMeters: bt.currentDistanceMeters)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }

        .navigationTitle("OBS Recorder")
        .navigationBarTitleDisplayMode(.inline)

        .sheet(isPresented: $showingInfo) {
            NavigationStack {
                InfoView()
                    .navigationTitle("Info")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }

        .safeAreaInset(edge: .bottom) {
            RecordButtonView(
                isConnected: isConnectedForUI,
                isRecording: bt.isRecording,
                onTap: handleRecordTap
            )
        }

        // MARK: - Watchdog wiring
        .onReceive(watchdogTimer) { _ in
            updateConnectionStaleness()
        }
        .onChange(of: bt.isConnected) { _, newValue in
            if newValue {
                lastSensorUpdate = Date()
                connectionIsStale = false
            } else {
                connectionIsStale = false
            }
        }

        // Wenn irgendein Sensorwert reinkommt/ändert: "lebt".
        .onChange(of: bt.overtakeDistanceCm) { _, _ in markSensorAlive() }
        .onChange(of: bt.leftRawCm) { _, _ in markSensorAlive() }
        .onChange(of: bt.rightRawCm) { _, _ in markSensorAlive() }
        .onChange(of: bt.leftCorrectedCm) { _, _ in markSensorAlive() }
        .onChange(of: bt.rightCorrectedCm) { _, _ in markSensorAlive() }
        .onChange(of: bt.currentDistanceMeters) { _, _ in markSensorAlive() }

        // Meldung aus BluetoothManager anzeigen (einmalig)
        .onChange(of: bt.userNotice) { _, newValue in
            guard let msg = newValue, !msg.isEmpty else { return }
            disconnectAlertText = msg
            showDisconnectAlert = true
        }
        .alert("Hinweis", isPresented: $showDisconnectAlert) {
            Button("OK", role: .cancel) {
                bt.userNotice = nil
            }
        } message: {
            Text(disconnectAlertText)
        }

        .onDisappear {
            toastTask?.cancel()
            toastTask = nil
        }
    }

    // MARK: - Actions

    @MainActor
    private func handleRecordTap() {
        guard isConnectedForUI else {
            Haptics.shared.warning()
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if bt.isRecording {
                bt.stopRecording()
                showSaveToastForTwoSeconds()
            } else {
                bt.startRecording()
            }
        }

        Haptics.shared.success()
    }

    private func showSaveToastForTwoSeconds() {
        toastTask?.cancel()
        showSaveConfirmation = true

        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { showSaveConfirmation = false }
            }
        }
    }

    // MARK: - Watchdog helpers

    private func markSensorAlive() {
        lastSensorUpdate = Date()
        if connectionIsStale {
            withAnimation(.easeInOut(duration: 0.2)) {
                connectionIsStale = false
            }
        }
    }

    private func updateConnectionStaleness() {
        guard bt.isConnected else {
            if connectionIsStale { connectionIsStale = false }
            return
        }

        let dt = Date().timeIntervalSince(lastSensorUpdate)
        let shouldBeStale = dt > staleAfterSeconds

        if shouldBeStale != connectionIsStale {
            withAnimation(.easeInOut(duration: 0.2)) {
                connectionIsStale = shouldBeStale
            }
        }
    }
}

// MARK: - Helpers

private func dashIfEmpty(_ s: String?) -> String {
    let trimmed = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "-" : trimmed
}

// MARK: - Logo

struct LogoView: View {

    let onInfoTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image("OBSLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("OBS Recorder")
                    .font(.obsSectionTitle)
            }

            Spacer()

            Button(action: onInfoTap) {
                Label("Info", systemImage: "info.circle")
                    .font(.obsFootnote.weight(.semibold))
                    .foregroundStyle(Color.obsAccentV2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color(.secondarySystemFill))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Info")
        }
        .obsCardStyleV2()
    }
}

// MARK: - Connection Status (Presentation Model)

struct ConnectionStatusPresentation {
    let title: String
    let summary: String
    let details: String?
    let color: Color
    let canShowDetails: Bool

    init(bt: BluetoothManager, isConnectionStale: Bool) {

        if bt.isConnected && isConnectionStale {
            title = "Verbindung verloren"
            summary = "Keine Sensordaten mehr empfangen."
            details = nil
            color = .obsWarnV2
            canShowDetails = false
            return
        }

        if bt.isConnected {
            title = "Mit OBS verbunden"
            color = .obsGoodV2
            canShowDetails = true

            let name = dashIfEmpty(bt.connectedName)
            let detected = bt.detectedDeviceType?.displayName ?? "unbekannt"
            summary = "\(name) · \(detected)"

            let mfg = dashIfEmpty(bt.manufacturerName)
            let fw  = dashIfEmpty(bt.firmwareRevision)

            details = """
            Name: \(bt.connectedName)
            LocalName: \(bt.connectedLocalName)
            Detected: \(detected) · Quelle: \(bt.lastBleSource)
            Hersteller: \(mfg) · Firmware: \(fw)
            ID: \(bt.connectedId)
            """
            return
        }

        if !bt.isPoweredOn {
            title = "Bluetooth deaktiviert"
            summary = "Aktiviere Bluetooth, um den Sensor zu verbinden."
            details = nil
            color = .obsDangerV2
            canShowDetails = false
            return
        }

        if !bt.hasBluetoothPermission {
            title = "Bluetooth-Zugriff erforderlich"
            summary = "Erlaube Bluetooth-Zugriff in den iOS-Einstellungen."
            details = nil
            color = .obsDangerV2
            canShowDetails = false
            return
        }

        title = "Nicht verbunden"
        summary = "Warten auf Sensorverbindung."
        details = nil
        color = .obsWarnV2
        canShowDetails = false
    }
}

struct ConnectionStatusCard: View {
    @EnvironmentObject var bt: BluetoothManager
    let isConnectionStale: Bool

    @State private var showDetails = false

    var body: some View {
        let p = ConnectionStatusPresentation(bt: bt, isConnectionStale: isConnectionStale)

        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .symbolVariant(.fill)
                .foregroundStyle(p.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text(p.title)
                    .font(.obsSectionTitle)

                Text(p.summary)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if p.canShowDetails, let details = p.details {
                    if showDetails {
                        Text(details)
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            showDetails.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showDetails ? "Details ausblenden" : "Details anzeigen")
                                .font(.obsFootnote.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(showDetails ? 180 : 0))
                        }
                        .foregroundStyle(Color.obsAccentV2)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .obsCardStyleV2()
    }
}

// MARK: - Permission Hints

struct LocationPermissionHintView: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.fill")
                .font(.title3)
                .foregroundStyle(Color.obsAccentV2)

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
        .obsCardStyleV2()
    }

    private var title: String {
        if !bt.isLocationEnabled { return "Standortdienste deaktiviert" }
        if !bt.hasLocationAlwaysPermission { return "Hintergrund-Standort deaktiviert" }
        return "Standortzugriff erforderlich"
    }

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

struct BluetoothPermissionHintView: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(Color.obsAccentV2)

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
        .obsCardStyleV2()
    }

    private var title: String {
        bt.isPoweredOn ? "Bluetooth-Zugriff erforderlich" : "Bluetooth deaktiviert"
    }

    private var message: String {
        if !bt.isPoweredOn {
            return "Aktiviere Bluetooth in den Systemeinstellungen, damit sich dein OBS-Gerät verbinden und Messwerte senden kann."
        }
        return "Damit sich dein OBS-Gerät verbinden kann, benötigt diese App Zugriff auf Bluetooth. Erlaube den Zugriff in den iOS-Einstellungen."
    }
}

// MARK: - Measurements Card

struct MeasurementsCardView: View {
    @EnvironmentObject var bt: BluetoothManager
    @Binding var showSideDistances: Bool

    let isConnectedForUI: Bool

    private var isWaitingForSideValues: Bool {
        showSideDistances
        && isConnectedForUI
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

                Toggle("Abstände anzeigen", isOn: $showSideDistances)
                    .labelsHidden()
                    .accessibilityLabel("Abstände links und rechts anzeigen")
            }

            if showSideDistances && (!isConnectedForUI || isWaitingForSideValues) {
                SensorValuesSkeletonView()
                    .transition(.opacity)
            }

            if showSideDistances {
                HStack(alignment: .top, spacing: 32) {
                    SensorValueView(
                        title: "Abstand links",
                        corrected: isConnectedForUI ? bt.leftCorrectedCm : nil,
                        raw: isConnectedForUI ? bt.leftRawCm : nil
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .redacted(reason: isWaitingForSideValues ? .placeholder : [])

                    SensorValueView(
                        title: "Abstand rechts",
                        corrected: isConnectedForUI ? bt.rightCorrectedCm : nil,
                        raw: isConnectedForUI ? bt.rightRawCm : nil
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .redacted(reason: isWaitingForSideValues ? .placeholder : [])
                }
            }

            OvertakeDistanceView(distance: isConnectedForUI ? bt.overtakeDistanceCm : nil)
        }
        .obsCardStyleV2()
    }
}

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

struct SensorValueView: View {
    let title: String
    let corrected: Int?
    let raw: Int?

    @State private var showMeasuredInfo = false
    @State private var showCalculatedInfo = false

    private let maxDistance = 200.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.obsSectionTitle)

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

                    ProgressView(
                        value: min(Double(corrected), maxDistance),
                        total: maxDistance
                    )
                    .tint(Color.obsOvertakeColorV2(for: corrected))

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
                Text("Noch kein berechneter Wert.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }

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
                Text("Noch kein Rohwert gemessen.")
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct OvertakeDistanceView: View {
    let distance: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Überholabstand")
                .font(.obsScreenTitle)

            if let distance {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.obsOvertakeColorV2(for: distance))
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

            Stepper(value: $handlebarWidthCm, in: 30...120, step: 1) {
                EmptyView()
            }
            .labelsHidden()

            Text("Wird zur Berechnung des Überholabstands verwendet.")
                .font(.obsFootnote)
                .foregroundStyle(.secondary)
        }
        .obsCardStyleV2()
    }
}

// MARK: - Record Button

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
                        ? [Color.obsDangerV2.opacity(0.95), Color.obsDangerV2]
                        : [Color.obsAccentV2.opacity(0.95), Color.obsAccentV2],
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
        .disabled(!isConnected)
        .opacity(isConnected ? 1.0 : 0.5)
    }
}

// MARK: - Save Confirmation Toast

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
