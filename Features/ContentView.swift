// ContentView.swift

import SwiftUI
import UIKit
import Combine

/// Haupt-UI der App.
/// Zeigt:
/// - Kompakter Header mit Status
/// - Hero-Anzeige Überholabstand
/// - Live-Statistik während Aufnahme
/// - Sensordetails (optional)
/// - Record-Button (Start/Stop Aufnahme)
struct ContentView: View {

    @EnvironmentObject var bt: BluetoothManager

    @State private var showSaveConfirmation = false
    @State private var showSideDistances = false
    @State private var showHandlebarSettings = false
    @State private var toastTask: Task<Void, Never>?
    @State private var showingSensorInfo = false
    @State private var showingAppInfo = false

    // MARK: - Connection Watchdog
    @State private var lastSensorUpdate: Date = .distantPast
    @State private var connectionIsStale = false
    private let staleAfterSeconds: TimeInterval = OBSTiming.sensorTimeout

    private var isConnectedForUI: Bool {
        bt.isConnected && !connectionIsStale
    }

    // MARK: - Alerts
    @State private var showDisconnectAlert = false
    @State private var disconnectAlertText = ""

    // MARK: - Recording Timer
    @State private var recordingDuration: TimeInterval = 0

    // Ein Timer für alles (Performance: nur 1 Timer statt 2)
    private let uiTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(spacing: 16) {
                    // Kompakter Header
                    CompactHeaderView(
                        isConnected: isConnectedForUI,
                        isStale: connectionIsStale,
                        deviceName: bt.connectedName,
                        onSensorInfoTap: { showingSensorInfo = true }
                    )

                    // Permission-Hinweise (falls nötig)
                    if !bt.isPoweredOn || !bt.hasBluetoothPermission {
                        BluetoothPermissionHintView()
                    }

                    // Hero-Überholabstand
                    HeroOvertakeView(
                        distance: isConnectedForUI ? bt.overtakeDistanceCm : nil,
                        isRecording: bt.isRecording
                    )

                    // Live-Stats während Aufnahme
                    if bt.isRecording {
                        LiveRecordingStatsView(
                            duration: recordingDuration,
                            distanceMeters: bt.currentDistanceMeters,
                            overtakeCount: bt.currentOvertakeCount
                        )
                    }

                    // Sensordetails (optional aufklappbar)
                    if showSideDistances {
                        SideDistancesCard(
                            leftCorrected: isConnectedForUI ? bt.leftCorrectedCm : nil,
                            leftRaw: isConnectedForUI ? bt.leftRawCm : nil,
                            rightCorrected: isConnectedForUI ? bt.rightCorrectedCm : nil,
                            rightRaw: isConnectedForUI ? bt.rightRawCm : nil
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Toggle für Seitenabstände
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showSideDistances.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "ruler")
                                .foregroundStyle(.secondary)
                            Text(showSideDistances ? "Seitenabstände ausblenden" : "Seitenabstände anzeigen")
                                .font(.obsFootnote)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(showSideDistances ? 180 : 0))
                        }
                        .foregroundStyle(Color.obsAccentV2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Lenkerbreite (einklappbar)
                    CollapsibleHandlebarView(
                        handlebarWidthCm: $bt.handlebarWidthCm,
                        isExpanded: $showHandlebarSettings
                    )

                    // Standort-Hinweis (falls nötig)
                    if !bt.isLocationEnabled || !bt.hasLocationAlwaysPermission {
                        LocationPermissionHintView()
                    }

                    // App-Info Link (dezent am Ende)
                    Button {
                        showingAppInfo = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.footnote)
                            Text("Über diese App")
                                .font(.obsFootnote)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)

            // Toast
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

        .sheet(isPresented: $showingSensorInfo) {
            SensorInfoSheet(
                isConnected: isConnectedForUI,
                isStale: connectionIsStale,
                deviceName: bt.connectedName,
                leftCorrected: bt.leftCorrectedCm,
                leftRaw: bt.leftRawCm,
                rightCorrected: bt.rightCorrectedCm,
                rightRaw: bt.rightRawCm,
                overtakeDistance: bt.overtakeDistanceCm
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }

        .sheet(isPresented: $showingAppInfo) {
            NavigationStack {
                InfoView()
                    .navigationTitle("Über diese App")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") { showingAppInfo = false }
                        }
                    }
            }
        }

        .safeAreaInset(edge: .bottom) {
            RecordButtonView(
                isConnected: isConnectedForUI,
                isRecording: bt.isRecording,
                recordingDuration: recordingDuration,
                onTap: handleRecordTap
            )
        }

        // UI Timer (Watchdog + Recording in einem)
        .onReceive(uiTimer) { _ in
            updateConnectionStaleness()
            updateRecordingDuration()
        }

        .onChange(of: bt.isConnected) { _, newValue in
            if newValue {
                lastSensorUpdate = Date()
                connectionIsStale = false
            } else {
                connectionIsStale = false
            }
        }

        // Nur ein onChange für Sensor-Aktivität (statt 6 separate)
        .onChange(of: bt.lastSensorPacketAt) { _, _ in markSensorAlive() }

        .onChange(of: bt.userNotice) { _, newValue in
            guard let msg = newValue, !msg.isEmpty else { return }
            disconnectAlertText = msg
            showDisconnectAlert = true
        }
        .alert("Hinweis", isPresented: $showDisconnectAlert) {
            Button("OK", role: .cancel) { bt.userNotice = nil }
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

    private func updateRecordingDuration() {
        guard let start = bt.recordingStartTime else {
            if recordingDuration != 0 { recordingDuration = 0 }
            return
        }
        recordingDuration = Date().timeIntervalSince(start)
    }
}

// MARK: - Compact Header

struct CompactHeaderView: View {
    let isConnected: Bool
    let isStale: Bool
    let deviceName: String
    let onSensorInfoTap: () -> Void

    private var statusColor: Color {
        if isStale { return .obsWarnV2 }
        if isConnected { return .obsGoodV2 }
        return .obsWarnV2
    }

    private var statusText: String {
        if isStale { return "Verbindung verloren" }
        if isConnected { return deviceName.isEmpty ? "Verbunden" : deviceName }
        return "Nicht verbunden"
    }

    private var statusIcon: String {
        if isStale { return "antenna.radiowaves.left.and.right.slash" }
        if isConnected { return "antenna.radiowaves.left.and.right" }
        return "antenna.radiowaves.left.and.right.slash"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Logo
            Image("OBSLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            // Status (tappable for sensor info)
            Button(action: onSensorInfoTap) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Hero Overtake Display

struct HeroOvertakeView: View {
    let distance: Int?
    let isRecording: Bool

    private let maxDistance: Double = 200.0

    private var displayColor: Color {
        guard let d = distance else { return .secondary }
        return Color.obsOvertakeColorV2(for: d)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Hauptwert
            VStack(spacing: 4) {
                if let distance {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(distance)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(displayColor)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: distance)

                        Text("cm")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text("Überholabstand")
                    .font(.obsBody)
                    .foregroundStyle(.secondary)
            }

            // Fortschrittsbalken
            if let distance {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Hintergrund
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.tertiarySystemFill))

                        // Fortschritt
                        RoundedRectangle(cornerRadius: 6)
                            .fill(displayColor)
                            .frame(width: min(CGFloat(distance) / maxDistance, 1.0) * geo.size.width)
                            .animation(.spring(response: 0.3), value: distance)
                    }
                }
                .frame(height: 12)
                .padding(.horizontal, 24)

                // Skala
                HStack {
                    Text("0")
                    Spacer()
                    Text("100")
                    Spacer()
                    Text("200 cm")
                }
                .font(.obsCaption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Live Recording Stats

struct LiveRecordingStatsView: View {
    let duration: TimeInterval
    let distanceMeters: Double
    let overtakeCount: Int

    private var formattedDuration: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private var formattedDistance: String {
        String(format: "%.2f", distanceMeters / 1000.0)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Recording Indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.obsDangerV2)
                    .frame(width: 10, height: 10)
                    .modifier(PulsingModifier())

                Text("REC")
                    .font(.obsCaption.weight(.bold))
                    .foregroundStyle(Color.obsDangerV2)

                Text(formattedDuration)
                    .font(.obsBody.monospacedDigit())
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 24)

            // Distance
            HStack(spacing: 4) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(formattedDistance) km")
                    .font(.obsBody.monospacedDigit())
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 24)

            // Events
            HStack(spacing: 4) {
                Image(systemName: "car.side")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(overtakeCount)")
                    .font(.obsBody.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Pulsierender Effekt für Recording-Indikator
struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Side Distances Card

struct SideDistancesCard: View {
    let leftCorrected: Int?
    let leftRaw: Int?
    let rightCorrected: Int?
    let rightRaw: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            SideDistanceColumn(
                title: "Links",
                corrected: leftCorrected,
                raw: leftRaw
            )
            .frame(maxWidth: .infinity)

            Divider()

            SideDistanceColumn(
                title: "Rechts",
                corrected: rightCorrected,
                raw: rightRaw
            )
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SideDistanceColumn: View {
    let title: String
    let corrected: Int?
    let raw: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.obsCaption)
                .foregroundStyle(.secondary)

            if let corrected {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(corrected)")
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text("cm")
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: min(Double(corrected), 200), total: 200)
                    .tint(Color.obsOvertakeColorV2(for: corrected))
            } else {
                Text("—")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let raw {
                Text("Roh: \(raw) cm")
                    .font(.obsCaption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Collapsible Handlebar

struct CollapsibleHandlebarView: View {
    @Binding var handlebarWidthCm: Int
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header (immer sichtbar)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "bicycle")
                        .foregroundStyle(.secondary)

                    Text("Lenkerbreite")
                        .font(.obsBody)

                    Spacer()

                    Text("\(handlebarWidthCm) cm")
                        .font(.obsBody.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Expanded Content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Stepper(value: $handlebarWidthCm, in: 30...120, step: 1) {
                        EmptyView()
                    }
                    .labelsHidden()

                    Text("Wird zur Berechnung des Überholabstands verwendet (Sensorabstand minus halbe Lenkerbreite).")
                        .font(.obsCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            return "Aktiviere die Standortdienste in den iOS-Einstellungen unter \"Datenschutz & Sicherheit > Ortungsdienste\"."
        }
        return "Für Hintergrund-Aufnahmen benötigt die App \"Immer\"-Zugriff auf den Standort. Stelle dies in den Einstellungen ein."
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
            return "Aktiviere Bluetooth in den Systemeinstellungen."
        }
        return "Erlaube Bluetooth-Zugriff in den iOS-Einstellungen."
    }
}

// MARK: - Record Button

struct RecordButtonView: View {
    let isConnected: Bool
    let isRecording: Bool
    let recordingDuration: TimeInterval
    let onTap: () -> Void

    private var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon mit pulsierendem Effekt während der Aufnahme
                ZStack {
                    if isRecording {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .scaleEffect(isRecording ? 1.2 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                value: isRecording
                            )
                    }

                    Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
                            .font(.obsSectionTitle)
                            .fontWeight(.semibold)

                        if isRecording {
                            Text(formattedDuration)
                                .font(.obsFootnote)
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }

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

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Aufnahme gespeichert")
                        .font(.obsFootnote.weight(.semibold))

                    Text("\(overtakeCount) Events · \(distanceText) km")
                        .font(.obsCaption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 8)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Sensor Info Sheet

struct SensorInfoSheet: View {
    let isConnected: Bool
    let isStale: Bool
    let deviceName: String
    let leftCorrected: Int?
    let leftRaw: Int?
    let rightCorrected: Int?
    let rightRaw: Int?
    let overtakeDistance: Int?

    @Environment(\.dismiss) private var dismiss

    private var statusColor: Color {
        if isStale { return .obsWarnV2 }
        if isConnected { return .obsGoodV2 }
        return .obsDangerV2
    }

    private var statusText: String {
        if isStale { return "Verbindung unterbrochen" }
        if isConnected { return "Verbunden" }
        return "Nicht verbunden"
    }

    private var statusDescription: String {
        if isStale {
            return "Der Sensor antwortet nicht mehr. Stelle sicher, dass er eingeschaltet und in Reichweite ist."
        }
        if isConnected {
            return "Der Sensor sendet Daten. Du kannst eine Aufnahme starten."
        }
        return "Schalte den OpenBikeSensor ein. Die Verbindung wird automatisch hergestellt."
    }

    var body: some View {
        NavigationStack {
            List {
                // Connection Status Section
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .font(.title2)
                            .foregroundStyle(statusColor)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusText)
                                .font(.obsBody.weight(.semibold))

                            if isConnected && !deviceName.isEmpty {
                                Text(deviceName)
                                    .font(.obsFootnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                    }
                    .padding(.vertical, 4)

                    Text(statusDescription)
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Verbindungsstatus")
                }

                // Live Data Section (only when connected)
                if isConnected && !isStale {
                    Section {
                        if let distance = overtakeDistance {
                            sensorDataRow(
                                label: "Überholabstand",
                                value: "\(distance) cm",
                                icon: "arrow.left.and.right"
                            )
                        }

                        if let left = leftCorrected {
                            sensorDataRow(
                                label: "Links (korrigiert)",
                                value: "\(left) cm",
                                icon: "arrow.left"
                            )
                        }

                        if let leftR = leftRaw {
                            sensorDataRow(
                                label: "Links (roh)",
                                value: "\(leftR) cm",
                                icon: "arrow.left",
                                secondary: true
                            )
                        }

                        if let right = rightCorrected {
                            sensorDataRow(
                                label: "Rechts (korrigiert)",
                                value: "\(right) cm",
                                icon: "arrow.right"
                            )
                        }

                        if let rightR = rightRaw {
                            sensorDataRow(
                                label: "Rechts (roh)",
                                value: "\(rightR) cm",
                                icon: "arrow.right",
                                secondary: true
                            )
                        }
                    } header: {
                        Text("Aktuelle Messwerte")
                    }
                }

                // Help Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verbindungsprobleme?")
                            .font(.obsBody.weight(.semibold))

                        Text("1. Stelle sicher, dass Bluetooth aktiviert ist\n2. Schalte den Sensor aus und wieder ein\n3. Warte einige Sekunden")
                            .font(.obsFootnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Sensor-Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func sensorDataRow(label: String, value: String, icon: String, secondary: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(secondary ? .tertiary : .secondary)
                .frame(width: 24)

            Text(label)
                .font(.obsBody)
                .foregroundStyle(secondary ? .secondary : .primary)

            Spacer()

            Text(value)
                .font(.obsBody.monospacedDigit())
                .foregroundStyle(secondary ? .secondary : .primary)
        }
    }
}
