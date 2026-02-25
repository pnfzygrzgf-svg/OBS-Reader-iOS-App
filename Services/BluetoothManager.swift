//
//  BluetoothManager.swift
//

import Foundation
import CoreBluetooth
import SwiftProtobuf
import Combine
import CoreLocation
import ActivityKit

// =====================================================
// MARK: - BLE UUIDs
// =====================================================

private let obsLiteServiceUUID  = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private let obsLiteCharTxUUID   = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

private let obsClassicServiceUUID        = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000000")
private let obsClassicDistanceCharUUID   = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000002")
private let obsClassicButtonCharUUID     = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000003")
private let obsClassicOffsetCharUUID     = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000004")
private let obsClassicTrackIdCharUUID    = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000005")

private let batteryServiceUUID           = CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")
private let batteryLevelCharUUID         = CBUUID(string: "00002A19-0000-1000-8000-00805F9B34FB")

private let deviceInfoServiceUUID        = CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB")
private let firmwareRevisionCharUUID     = CBUUID(string: "00002A26-0000-1000-8000-00805F9B34FB")
private let manufacturerNameCharUUID     = CBUUID(string: "00002A29-0000-1000-8000-00805F9B34FB")

// =====================================================
// MARK: - Gerätetyp (nur Anzeige/Auto-Detect)
// =====================================================

enum ObsDeviceType: String, CaseIterable, Identifiable {
    case lite
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lite:    return "OBS Lite"
        case .classic: return "OBS Classic"
        }
    }

    var description: String {
        switch self {
        case .lite:
            return "Verwendet OBS Lite mit Protobuf/BIN-Datei."
        case .classic:
            return "Verwendet OBS Classic und speichert Daten als CSV."
        }
    }
}

// =====================================================
// MARK: - BluetoothManager
// =====================================================

final class BluetoothManager: NSObject, ObservableObject {

    // -------------------------------------------------
    // MARK: Live Activity
    // -------------------------------------------------

    private let live = LiveActivityManager()

    /// Zeitpunkt des letzten "echten" Sensorpakets (für "Sensor aktiv")
    @Published var lastSensorPacketAt: Date?

    /// Heuristik: Sensor gilt als aktiv, wenn in den letzten 5 Sekunden ein Paket kam.
    private var sensorActiveNow: Bool {
        guard isConnected, let t = lastSensorPacketAt else { return false }
        return Date().timeIntervalSince(t) < 5
    }

    private var liveSessionId: String?

    /// Aufnahmetyp für die aktuelle Session (damit stopRecording weiß, was zu finalisieren ist).
    private var recordingDeviceType: ObsDeviceType?
    
    /// Merkt sich, ob vor Disconnect eine Aufnahme lief → Auto-Restart nach Reconnect
    private var shouldRestartRecordingOnReconnect: Bool = false

    /// Speichert den Gerätetyp für Auto-Restart (da recordingDeviceType nach stopRecording nil ist)
    private var deviceTypeForRestart: ObsDeviceType?

    /// Lock für thread-safe Start/Stop Recording
    private let recordingLock = NSLock()

    // -------------------------------------------------
    // MARK: Published State (SwiftUI)
    // -------------------------------------------------

    @Published var isPoweredOn: Bool = false
    @Published var isConnected: Bool = false

    @Published var isRecording: Bool = false
    @Published var recordingStartTime: Date?

    @Published var hasBluetoothPermission: Bool = true

    @Published var isLocationEnabled: Bool = false
    @Published var hasLocationAlwaysPermission: Bool = false

    @Published var lastEvent: Openbikesensor_Event?
    @Published var lastError: String?

    // Einmalige Meldung für die UI
    @Published var userNotice: String?

    @Published var lastDistanceText: String = "Noch keine Messung. Starte eine Aufnahme, um Werte zu sehen."
    @Published var lastMessageText: String = ""

    @Published var leftDistanceText: String = "Links: Noch keine Messung."
    @Published var rightDistanceText: String = "Rechts: Noch keine Messung."
    @Published var overtakeDistanceText: String = "Überholabstand: Noch keine Messung."

    @Published var lastMinimumAtPressCm: Int?

    @Published var leftRawCm: Int?
    @Published var leftCorrectedCm: Int?

    @Published var rightRawCm: Int?
    @Published var rightCorrectedCm: Int?

    @Published var overtakeDistanceCm: Int?

    @Published var handlebarWidthCm: Int = 60 {
        didSet {
            if handlebarWidthCm < 30 { handlebarWidthCm = 30 }
            if handlebarWidthCm > 120 { handlebarWidthCm = 120 }
            UserDefaults.standard.set(handlebarWidthCm, forKey: "handlebarWidthCm")
        }
    }

    @Published var sensorsSwapped: Bool = false {
        didSet {
            UserDefaults.standard.set(sensorsSwapped, forKey: "sensorsSwapped")
        }
    }

    @Published var currentOvertakeCount: Int = 0
    @Published var currentDistanceMeters: Double = 0

    @Published var batteryLevelPercent: Int?
    @Published var firmwareRevision: String?
    @Published var manufacturerName: String?

    @Published var connectedName: String = "-"
    @Published var connectedLocalName: String = "-"
    @Published var connectedId: String = "-"
    @Published var connectedRSSI: Int?
    @Published var detectedDeviceType: ObsDeviceType?
    @Published var lastBleSource: String = "-"

    // =====================================================
    // MARK: - Live-Karten-Events
    // =====================================================

    @Published var liveOvertakeEvents: [OvertakeEvent] = []
    @Published var lastOvertakeAt: Date?

    // -------------------------------------------------
    // MARK: Private BLE State
    // -------------------------------------------------

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    private var classicDistanceChar: CBCharacteristic?
    private var classicButtonChar: CBCharacteristic?
    private var classicOffsetChar: CBCharacteristic?
    private var classicTrackIdChar: CBCharacteristic?

    private let locationManager = CLLocationManager()

    // Lite BIN Recorder (Protobuf->COBS->OBSFileWriter)
    private let liteRecorder = LiteBinRecorder()

    // Classic CSV bleibt eigene Datei
    private var classicCsvRecorder: ClassicCsvRecorder?

    private var lastLocation: CLLocation?

    private var timeWindowMinimum = TimeWindowMinimum(windowSeconds: 5.0)       // Source ID 1 (overtaker/links)
    private var timeWindowMinimumRight = TimeWindowMinimum(windowSeconds: 5.0)  // Source ID 2 (stationary/rechts)
    private var lastButtonPressAt: Date?  // Für Portal-Kompatibilität: Zeitfenster beginnt nach letztem Tastendruck

    // -------------------------------------------------
    // MARK: Connection Watchdog
    // -------------------------------------------------

    private var lastConnectAt: Date?
    private let connectionStaleAfter: TimeInterval = 6.5

    private var watchdogCancellable: AnyCancellable?
    private var isForcingDisconnect = false

    // -------------------------------------------------
    // MARK: Init
    // -------------------------------------------------

    override init() {
        super.init()

        let stored = UserDefaults.standard.integer(forKey: "handlebarWidthCm")
        if stored != 0 { handlebarWidthCm = stored }

        sensorsSwapped = UserDefaults.standard.bool(forKey: "sensorsSwapped")

        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )

        locationManager.delegate = self
        updateLocationAuthorizationStatus()

        watchdogCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.watchdogTick()
            }
    }

    deinit {
        watchdogCancellable?.cancel()
        if #available(iOS 16.1, *) {
            Task {
                await live.stop()
            }
        }
    }

    // -------------------------------------------------
    // MARK: Main-thread helper
    // -------------------------------------------------

    @inline(__always)
    private func ui(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() }
        else { DispatchQueue.main.async(execute: block) }
    }

    // -------------------------------------------------
    // MARK: Throttled UI Updates (Performance)
    // -------------------------------------------------

    /// Letzte UI-Aktualisierung für Sensor-Werte
    private var lastSensorUIUpdate: Date = .distantPast

    /// Minimum-Intervall zwischen UI-Updates (100ms = max 10 Updates/Sekunde)
    private let sensorUIUpdateInterval: TimeInterval = 0.1

    /// Gepufferte Sensor-Werte für das nächste UI-Update
    private var pendingLeftRaw: Int?
    private var pendingLeftCorrected: Int?
    private var pendingRightRaw: Int?
    private var pendingRightCorrected: Int?
    private var pendingOvertakeDistance: Int?
    private var hasPendingSensorUpdate = false

    /// Aktualisiert Sensor-Werte mit Throttling (max 10x pro Sekunde)
    private func throttledSensorUpdate(
        leftRaw: Int? = nil,
        leftCorrected: Int? = nil,
        rightRaw: Int? = nil,
        rightCorrected: Int? = nil,
        overtakeDistance: Int? = nil
    ) {
        // Werte puffern
        if leftRaw != nil { pendingLeftRaw = leftRaw }
        if leftCorrected != nil { pendingLeftCorrected = leftCorrected }
        if rightRaw != nil { pendingRightRaw = rightRaw }
        if rightCorrected != nil { pendingRightCorrected = rightCorrected }
        if overtakeDistance != nil { pendingOvertakeDistance = overtakeDistance }
        hasPendingSensorUpdate = true

        // Prüfen ob genug Zeit vergangen ist
        let now = Date()
        guard now.timeIntervalSince(lastSensorUIUpdate) >= sensorUIUpdateInterval else {
            return
        }

        // UI aktualisieren
        flushPendingSensorUpdates()
    }

    /// Schreibt gepufferte Sensor-Werte in die @Published Properties
    private func flushPendingSensorUpdates() {
        guard hasPendingSensorUpdate else { return }

        lastSensorUIUpdate = Date()
        hasPendingSensorUpdate = false

        ui { [self] in
            if let v = pendingLeftRaw { self.leftRawCm = v }
            if let v = pendingLeftCorrected { self.leftCorrectedCm = v }
            if let v = pendingRightRaw { self.rightRawCm = v }
            if let v = pendingRightCorrected { self.rightCorrectedCm = v }
            if let v = pendingOvertakeDistance { self.overtakeDistanceCm = v }
        }
    }

    // -------------------------------------------------
    // MARK: Reset bei Disconnect ( Live + Count/Distance auf 0)
    // -------------------------------------------------

    private func resetAfterDisconnect() {
        ui {
            self.leftRawCm = nil
            self.leftCorrectedCm = nil
            self.rightRawCm = nil
            self.rightCorrectedCm = nil
            self.overtakeDistanceCm = nil
            self.lastMinimumAtPressCm = nil

            self.leftDistanceText = "Links: Noch keine Messung."
            self.rightDistanceText = "Rechts: Noch keine Messung."
            self.overtakeDistanceText = "Überholabstand: Noch keine Messung."
            self.lastDistanceText = "Noch keine Messung. Starte eine Aufnahme, um Werte zu sehen."
            self.lastMessageText = ""

            self.lastEvent = nil

            // beides auf Null bei Disconnect
            self.currentOvertakeCount = 0
            self.currentDistanceMeters = 0
            self.lastLocation = nil

            self.liveOvertakeEvents.removeAll()
            self.lastOvertakeAt = nil

            self.lastSensorPacketAt = nil

            self.connectedRSSI = nil
            self.lastBleSource = "-"
        }

        timeWindowMinimum.reset()
        timeWindowMinimumRight.reset()
    }

    // -------------------------------------------------
    // MARK: Disconnect -> Aufnahme beenden + Auto-Restart merken
    // -------------------------------------------------

    private func stopRecordingDueToDisconnect() {
        guard isRecording else { return }

        // Gerätetyp VORHER speichern, da stopRecording() ihn auf nil setzt
        deviceTypeForRestart = recordingDeviceType

        stopRecording()

        // NACH stopRecording setzen, da stopRecording() das Flag auf false setzt
        shouldRestartRecordingOnReconnect = true

        // Meldung anpassen: User weiß, dass es automatisch weitergeht
        ui {
            self.userNotice = "Verbindung zum Sensor verloren: Aufnahme wurde gespeichert. Neue Aufnahme startet automatisch bei Reconnect."
        }

        // Nach Disconnect: alles leeren + Count/Distance = 0
        resetAfterDisconnect()
    }

    // =====================================================
    // MARK: Public API (Karte)
    // =====================================================

    func clearLiveOvertakeEvents() {
        ui {
            self.liveOvertakeEvents.removeAll()
            self.lastOvertakeAt = nil
        }
    }

    // -------------------------------------------------
    // MARK: Recording API
    // -------------------------------------------------

    func startRecording() {
        recordingLock.lock()
        defer { recordingLock.unlock() }

        // Doppelstart verhindern
        guard !isRecording else { return }

        guard isConnected else {
            ui { self.userNotice = "Kein Sensor verbunden." }
            return
        }

        guard let t = detectedDeviceType else {
            ui { self.userNotice = "Kein kompatibles OBS-Gerät erkannt." }
            return
        }

        ui {
            self.currentOvertakeCount = 0
            self.currentDistanceMeters = 0
            self.lastLocation = nil

            self.liveOvertakeEvents.removeAll()
            self.lastOvertakeAt = nil

            self.isRecording = true
            self.recordingStartTime = Date()
        }

        recordingDeviceType = t

        switch t {
        case .lite:
            liteRecorder.startSession()

        case .classic:
            let halfHandlebar = handlebarWidthCm / 2
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let recorder = ClassicCsvRecorder(
                handlebarOffsetCm: halfHandlebar,
                appVersion: appVersion,
                firmwareVersion: firmwareRevision
            )
            classicCsvRecorder = recorder
            recorder.startSession()
        }

        if #available(iOS 16.1, *) {
            let sessionId = UUID().uuidString
            liveSessionId = sessionId

            Task { @MainActor in
                live.start(
                    sessionId: sessionId,
                    lastOvertakeCm: self.overtakeDistanceCm,
                    sensorActive: self.sensorActiveNow,
                    lastPacketAt: self.lastSensorPacketAt,
                    recordingStartTime: self.recordingStartTime,
                    overtakeCount: self.currentOvertakeCount,
                    distanceMeters: self.currentDistanceMeters
                )
            }
        }
    }

    func stopRecording() {
        recordingLock.lock()
        defer { recordingLock.unlock() }

        // Doppelstop verhindern
        guard isRecording else { return }

        // Manuelles Stoppen → kein Auto-Restart
        shouldRestartRecordingOnReconnect = false

        let t = recordingDeviceType

        switch t {
        case .some(.lite):
            liteRecorder.finishSession()
        case .some(.classic):
            classicCsvRecorder?.finishSession()
        case .none:
            break
        }

        let fileURL: URL?
        switch t {
        case .some(.lite):
            fileURL = liteRecorder.fileURL
        case .some(.classic):
            fileURL = classicCsvRecorder?.fileURL
        case .none:
            fileURL = nil
        }

        if let url = fileURL {
            let hasCount = currentOvertakeCount > 0
            let hasDistance = currentDistanceMeters > 0.0

            if hasCount || hasDistance {
                OvertakeStatsStore.store(
                    count: hasCount ? currentOvertakeCount : nil,
                    distanceMeters: hasDistance ? currentDistanceMeters : nil,
                    for: url
                )
            }
        }

        ui {
            self.isRecording = false
            self.recordingStartTime = nil
        }

        if #available(iOS 16.1, *) {
            Task { @MainActor in
                await live.stop()
            }
        }

        liveSessionId = nil
        recordingDeviceType = nil
    }

    // -------------------------------------------------
    // MARK: GPS
    // -------------------------------------------------

    func handleLocationUpdate(_ location: CLLocation) {
        guard isRecording else { return }

        ui {
            if let prev = self.lastLocation {
                let segment = location.distance(from: prev)
                // Minimum 3m um GPS-Rauschen zu filtern, Maximum 2000m für Plausibilität
                if segment > 3, segment < 2000 {
                    self.currentDistanceMeters += segment
                }
            }
            self.lastLocation = location
        }

        // Nur Lite schreibt Geo ins BIN
        guard recordingDeviceType == .lite else { return }

        var geo = Openbikesensor_Geolocation()
        geo.latitude = location.coordinate.latitude
        geo.longitude = location.coordinate.longitude
        geo.altitude = location.altitude
        geo.groundSpeed = Float(max(location.speed, 0))
        geo.hdop = Float(location.horizontalAccuracy)

        var t = Openbikesensor_Time()
        let ts = location.timestamp.timeIntervalSince1970
        let sec = Int64(ts)
        let nanos = Int32((ts - Double(sec)) * 1_000_000_000)
        t.sourceID = 3
        t.seconds = sec
        t.nanoseconds = nanos
        t.reference = .unix

        var event = Openbikesensor_Event()
        event.geolocation = geo
        event.time = [t]

        // Recorder ergänzt Time ohnehin nochmal; das ist unkritisch,
        // aber wenn du doppelte Times vermeiden willst: hier event.time = [] setzen.
        liteRecorder.record(event: event, handlebarWidthCm: handlebarWidthCm)
    }

    // =====================================================
    // MARK: Live Marker setzen
    // =====================================================

    private func appendLiveOvertakeEvent(distanceCm: Int?) {
        guard let loc = self.lastLocation else { return }
        let distanceMeters = distanceCm.map { Double($0) / 100.0 }

        let ev = OvertakeEvent(
            coordinate: loc.coordinate,
            distance: distanceMeters
        )

        ui {
            self.liveOvertakeEvents.append(ev)
            if self.liveOvertakeEvents.count > 500 {
                self.liveOvertakeEvents.removeFirst(self.liveOvertakeEvents.count - 500)
            }
        }
    }

    // -------------------------------------------------
    // MARK: Location-Berechtigung
    // -------------------------------------------------

    private func updateLocationAuthorizationStatus() {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        let hasAlways = (status == .authorizedAlways)

        DispatchQueue.global(qos: .utility).async {
            let servicesEnabled = CLLocationManager.locationServicesEnabled()
            DispatchQueue.main.async {
                self.isLocationEnabled = servicesEnabled
                self.hasLocationAlwaysPermission = hasAlways
            }
        }
    }

    // -------------------------------------------------
    // MARK: Scanning immer broad
    // -------------------------------------------------

    private func stopScan() {
        central?.stopScan()
    }

    private func startBroadScan() {
        guard let central = central else { return }
        guard isPoweredOn, hasBluetoothPermission else { return }

        print("Starting BROAD scan (connect-then-verify)")

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    // -------------------------------------------------
    // MARK: Watchdog
    // -------------------------------------------------

    private func watchdogTick() {
        guard isConnected else { return }
        guard hasBluetoothPermission, isPoweredOn else { return }
        guard let p = peripheral else { return }

        if p.state != .connected {
            print(">> Watchdog: peripheral.state != .connected (\(p.state.rawValue))")
            stopRecordingDueToDisconnect()
            if !isRecording { resetAfterDisconnect() }
            forceDisconnectAndRescan(reason: "Verbindung verloren")
            return
        }

        let now = Date()

        if lastSensorPacketAt == nil {
            if let t0 = lastConnectAt, now.timeIntervalSince(t0) > connectionStaleAfter {
                print(">> Watchdog: no sensor packets after connect -> force disconnect")
                stopRecordingDueToDisconnect()
                if !isRecording { resetAfterDisconnect() }
                forceDisconnectAndRescan(reason: "Keine Sensordaten (Timeout)")
            }
            return
        }

        if let last = lastSensorPacketAt, now.timeIntervalSince(last) > connectionStaleAfter {
            print(">> Watchdog: sensor packets stale (\(now.timeIntervalSince(last))s) -> force disconnect")
            stopRecordingDueToDisconnect()
            if !isRecording { resetAfterDisconnect() }
            forceDisconnectAndRescan(reason: "Sensor nicht erreichbar (Timeout)")
        }
    }

    private func forceDisconnectAndRescan(reason: String) {
        guard let central = central else { return }
        guard let p = peripheral else { return }
        guard !isForcingDisconnect else { return }

        isForcingDisconnect = true

        ui {
            self.isConnected = false
            self.lastError = reason
            self.detectedDeviceType = nil
            self.lastBleSource = "-"
        }

        if !isRecording {
            resetAfterDisconnect()
        }

        if #available(iOS 16.1, *) {
            Task { @MainActor in
                await self.live.stop()
            }
        }
        self.liveSessionId = nil

        central.cancelPeripheralConnection(p)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(OBSTiming.reconnectDelay))
            guard let self else { return }
            guard self.isForcingDisconnect else { return }

            self.isForcingDisconnect = false

            self.peripheral = nil
            self.lastConnectAt = nil
            self.lastSensorPacketAt = nil

            self.startBroadScan()
        }
    }
    
    // -------------------------------------------------
    // MARK: Auto-Restart Recording nach Reconnect
    // -------------------------------------------------
    
    private func tryAutoRestartRecording() {
        guard shouldRestartRecordingOnReconnect else { return }
        guard isConnected else { return }
        guard detectedDeviceType != nil else { return }

        shouldRestartRecordingOnReconnect = false
        deviceTypeForRestart = nil  // Aufräumen

        startRecording()

        ui {
            self.userNotice = "Verbindung wiederhergestellt: Neue Aufnahme gestartet."
        }

        print(">> Auto-restart recording after reconnect")
    }
}

// =====================================================
// MARK: - CBCentralManagerDelegate
// =====================================================

extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let hasPermission: Bool
        if #available(iOS 13.0, *) {
            let auth = CBCentralManager.authorization
            hasPermission = (auth == .allowedAlways)
        } else {
            hasPermission = true
        }

        ui {
            self.hasBluetoothPermission = hasPermission
            self.isPoweredOn = (central.state == .poweredOn)

            if central.state != .poweredOn {
                self.stopRecordingDueToDisconnect()
                self.isConnected = false
                if !self.isRecording {
                    self.resetAfterDisconnect()
                }
            }
        }

        print("centralManagerDidUpdateState: state=\(central.state.rawValue) perm=\(hasPermission)")

        guard central.state == .poweredOn, hasPermission else { return }
        startBroadScan()
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "-"
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true

        if self.peripheral != nil { return }
        if !isConnectable { return }

        let name = (peripheral.name ?? "").lowercased()
        let ln = localName.lowercased()

        // Broad-scan: nur Kandidaten verbinden, die nach OBS aussehen.
        let looksObs = name.contains("obs")
        || ln.contains("obs")
        || ln.contains("openbikesensor")
        || name.contains("openbikesensor")

        if !looksObs { return }

        print(">> didDiscover candidate: \(peripheral.name ?? "unknown") rssi=\(RSSI) localName=\(localName)")

        ui {
            self.connectedName = peripheral.name ?? "-"
            self.connectedLocalName = localName
            self.connectedId = peripheral.identifier.uuidString
            self.connectedRSSI = RSSI.intValue
            self.detectedDeviceType = nil
            self.lastBleSource = "-"
        }

        self.peripheral = peripheral
        self.peripheral?.delegate = self

        stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        print(">> didConnect \(peripheral.identifier)")

        ui {
            self.isConnected = true
            self.lastError = nil
            self.connectedName = peripheral.name ?? self.connectedName
            self.connectedId = peripheral.identifier.uuidString
        }

        lastConnectAt = Date()
        lastSensorPacketAt = nil
        isForcingDisconnect = false

        peripheral.discoverServices(nil)

        // Timeout für Service Discovery
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(OBSTiming.sensorTimeout))
            guard let self else { return }
            // Nur trennen wenn verbunden aber kein Gerätetyp erkannt
            guard self.isConnected, self.detectedDeviceType == nil else { return }

            print(">> Service Discovery Timeout")
            self.forceDisconnectAndRescan(reason: "Service Discovery Timeout")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print(">> didFailToConnect: \(error?.localizedDescription ?? "unknown error")")

        ui {
            self.isConnected = false
            self.lastError = error?.localizedDescription ?? "Verbindung fehlgeschlagen"
        }

        lastConnectAt = nil
        lastSensorPacketAt = nil
        isForcingDisconnect = false

        resetAfterDisconnect()

        self.peripheral = nil
        startBroadScan()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print(">> didDisconnect \(peripheral.identifier) error=\(String(describing: error))")

        stopRecordingDueToDisconnect()

        ui {
            self.isConnected = false
            if let error = error, !self.isForcingDisconnect {
                self.lastError = error.localizedDescription
            }
            self.detectedDeviceType = nil
            self.lastBleSource = "-"
        }

        // Auch wenn nicht recording: Werte/Count/Dist leeren
        if !isRecording {
            resetAfterDisconnect()
        }

        lastConnectAt = nil
        lastSensorPacketAt = nil
        isForcingDisconnect = false

        if #available(iOS 16.1, *) {
            Task { @MainActor in
                await self.live.stop()
            }
        }
        self.liveSessionId = nil

        self.peripheral = nil
        startBroadScan()
    }
}

// =====================================================
// MARK: - CBPeripheralDelegate
// =====================================================

extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        if let error = error {
            ui { self.lastError = "Service-Fehler: \(error.localizedDescription)" }
            return
        }

        guard let services = peripheral.services else { return }

        let uuids = Set(services.map { $0.uuid })
        let hasClassic = uuids.contains(obsClassicServiceUUID)
        let hasLite = uuids.contains(obsLiteServiceUUID)

        ui {
            if hasClassic { self.detectedDeviceType = .classic }
            else if hasLite { self.detectedDeviceType = .lite }
            else { self.detectedDeviceType = nil }
        }

        // Nicht kompatibel -> trennen
        guard hasClassic || hasLite else {
            ui { self.lastError = "Nicht kompatibles Gerät (kein OBS Service)." }
            central?.cancelPeripheralConnection(peripheral)
            return
        }

        for service in services {
            print(">> discovered service \(service.uuid)")

            switch service.uuid {
            case obsLiteServiceUUID:
                peripheral.discoverCharacteristics([obsLiteCharTxUUID], for: service)

            case obsClassicServiceUUID:
                peripheral.discoverCharacteristics(
                    [
                        obsClassicDistanceCharUUID,
                        obsClassicButtonCharUUID,
                        obsClassicOffsetCharUUID,
                        obsClassicTrackIdCharUUID
                    ],
                    for: service
                )

            case batteryServiceUUID:
                peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)

            case deviceInfoServiceUUID:
                peripheral.discoverCharacteristics(
                    [firmwareRevisionCharUUID, manufacturerNameCharUUID],
                    for: service
                )

            default:
                break
            }
        }
        
        // Auto-Restart Recording nach Reconnect (sobald Gerätetyp erkannt)
        if hasClassic || hasLite {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(OBSTiming.debounceDelay))
                self?.tryAutoRestartRecording()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            ui { self.lastError = "Char-Fehler: \(error.localizedDescription)" }
            return
        }

        guard let characteristics = service.characteristics else { return }

        print(">> discovered chars for service \(service.uuid)")
        for char in characteristics {
            print("   char \(char.uuid)")

            switch char.uuid {
            case obsLiteCharTxUUID:
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                } else {
                    print("WARNING: \(char.uuid) unterstützt notify nicht")
                }

            case obsClassicDistanceCharUUID:
                classicDistanceChar = char
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }

            case obsClassicButtonCharUUID:
                classicButtonChar = char
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }

            case obsClassicOffsetCharUUID:
                classicOffsetChar = char
                peripheral.readValue(for: char)

            case obsClassicTrackIdCharUUID:
                classicTrackIdChar = char
                peripheral.readValue(for: char)

            case batteryLevelCharUUID:
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }
                peripheral.readValue(for: char)

            case firmwareRevisionCharUUID:
                peripheral.readValue(for: char)

            case manufacturerNameCharUUID:
                peripheral.readValue(for: char)

            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            ui { self.lastError = "Notify-Fehler: \(error.localizedDescription)" }
        } else {
            print(">> notify state updated for \(characteristic.uuid), isNotifying=\(characteristic.isNotifying)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        if let error = error {
            ui { self.lastError = "Update-Fehler: \(error.localizedDescription)" }
            return
        }

        guard let data = characteristic.value else { return }

        ui {
            switch characteristic.uuid {
            case obsLiteCharTxUUID, obsClassicDistanceCharUUID, obsClassicButtonCharUUID:
                self.lastSensorPacketAt = Date()
            default:
                break
            }
        }

        ui {
            switch characteristic.uuid {
            case obsLiteCharTxUUID:              self.lastBleSource = "Lite TX (Protobuf)"
            case obsClassicDistanceCharUUID:     self.lastBleSource = "Classic Distance"
            case obsClassicButtonCharUUID:       self.lastBleSource = "Classic Button"
            case batteryLevelCharUUID:           self.lastBleSource = "Battery"
            case firmwareRevisionCharUUID:       self.lastBleSource = "Firmware"
            case manufacturerNameCharUUID:       self.lastBleSource = "Manufacturer"
            default:                             self.lastBleSource = characteristic.uuid.uuidString
            }
        }

        switch characteristic.uuid {
        case obsLiteCharTxUUID:
            handleLiteUpdate(data)

        case obsClassicDistanceCharUUID:
            handleClassicDistanceUpdate(data)

        case obsClassicButtonCharUUID:
            handleClassicButtonUpdate(data)

        case obsClassicOffsetCharUUID:
            handleClassicOffsetUpdate(data)

        case obsClassicTrackIdCharUUID:
            handleClassicTrackIdUpdate(data)

        case batteryLevelCharUUID:
            handleBatteryUpdate(data)

        case firmwareRevisionCharUUID:
            handleFirmwareUpdate(data)

        case manufacturerNameCharUUID:
            handleManufacturerUpdate(data)

        default:
            break
        }
    }

    // -------------------------------------------------
    // MARK: - Lite Pfad (Protobuf -> BIN via LiteBinRecorder)
    // -------------------------------------------------

    private func handleLiteUpdate(_ data: Data) {
        // --- TEMP DEBUG: Rohe BLE-Bytes loggen ---
        if case .distanceMeasurement(let dmRaw) = (try? Openbikesensor_Event(serializedData: data))?.content {
            let hex = data.map { String(format: "%02x", $0) }.joined()
            if dmRaw.distance == 0.0 {
                print("🔴 BLE RAW ZERO: sid=\(dmRaw.sourceID) dist=\(dmRaw.distance) bytes=\(data.count) hex=\(hex)")
            } else {
                print("🟢 BLE RAW OK:   sid=\(dmRaw.sourceID) dist=\(dmRaw.distance) bytes=\(data.count)")
            }
        }
        // --- END TEMP DEBUG ---

        do {
            var event = try Openbikesensor_Event(serializedData: data)

            // --- TEMP DEBUG: Nach swap loggen ---
            if case .distanceMeasurement(let dmBefore) = event.content, dmBefore.distance == 0.0 {
                print("🔴 PRE-SWAP ZERO: sid=\(dmBefore.sourceID) dist=\(dmBefore.distance)")
            }
            // --- END TEMP DEBUG ---

            // Sensoren tauschen wenn aktiviert (sourceID 1 ↔ 2)
            if sensorsSwapped, case .distanceMeasurement(var dm) = event.content {
                if dm.sourceID == 1 { dm.sourceID = 2 }
                else if dm.sourceID == 2 { dm.sourceID = 1 }
                event.distanceMeasurement = dm
            }

            // --- TEMP DEBUG: Nach swap loggen ---
            if case .distanceMeasurement(let dmAfter) = event.content, dmAfter.distance == 0.0 {
                print("🔴 POST-SWAP ZERO: sid=\(dmAfter.sourceID) dist=\(dmAfter.distance)")
            }
            // --- END TEMP DEBUG ---

            ui {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }

            // BIN schreiben nur wenn Lite-Aufnahme läuft
            if isRecording, recordingDeviceType == .lite {
                // DistanceMeasurement ohne distance-Feld nicht schreiben
                // (Proto3 Default 0.0 vergiftet das min() im Portal)
                if case .distanceMeasurement(let dm) = event.content, dm.distance <= 0.0 {
                    return
                }

                // UserInput-Events nur schreiben wenn beide Sensoren Messungen im 5s-Fenster haben
                // (Portal benötigt min() beider Sensoren, crasht sonst mit "min() iterable argument is empty")
                if case .userInput(_) = event.content {
                    let hasOvertaker = timeWindowMinimum.currentMinimum != nil
                    let hasStationary = timeWindowMinimumRight.currentMinimum != nil

                    if !hasOvertaker || !hasStationary {
                        print("UserInput NICHT geschrieben: overtaker=\(hasOvertaker), stationary=\(hasStationary)")
                        ui {
                            self.userNotice = "Überholvorgang nicht gespeichert: Keine gültigen Sensordaten im Zeitfenster."
                        }
                        return
                    }
                }

                liteRecorder.record(event: event, handlebarWidthCm: handlebarWidthCm)
            }

        } catch {
            let msg = "Protobuf-Decode-Fehler (Lite): \(error.localizedDescription)"
            ui { self.lastError = msg }
            print(msg)
        }
    }

    // -------------------------------------------------
    // MARK: - Classic Pfad (8-Byte-Pakete -> CSV)
    // -------------------------------------------------

    func parseClassicPacket(_ data: Data) -> (clockMs: UInt32, leftCm: UInt16, rightCm: UInt16)? {
        guard data.count == 8 else { return nil }
        let bytes = [UInt8](data)

        let clock = UInt32(bytes[0])
        | (UInt32(bytes[1]) << 8)
        | (UInt32(bytes[2]) << 16)
        | (UInt32(bytes[3]) << 24)

        let left = UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)
        let right = UInt16(bytes[6]) | (UInt16(bytes[7]) << 8)

        return (clock, left, right)
    }

    func handleClassicDistanceUpdate(_ data: Data) {
        guard let packet = parseClassicPacket(data) else { return }

        // Sensoren tauschen wenn aktiviert
        let effectiveLeft  = sensorsSwapped ? packet.rightCm : packet.leftCm
        let effectiveRight = sensorsSwapped ? packet.leftCm  : packet.rightCm

        let leftMeters: Double?  = (effectiveLeft  == 0xFFFF) ? nil : Double(effectiveLeft)  / 100.0
        let rightMeters: Double? = (effectiveRight == 0xFFFF) ? nil : Double(effectiveRight) / 100.0

        // Preview/State: wie gehabt als DistanceMeasurement Events „simulieren"
        if let dist = leftMeters {
            var dm = Openbikesensor_DistanceMeasurement()
            dm.sourceID = 1
            dm.distance = Float(dist)

            var event = Openbikesensor_Event()
            event.distanceMeasurement = dm

            ui {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }
        }

        if let dist = rightMeters {
            var dm = Openbikesensor_DistanceMeasurement()
            dm.sourceID = 2
            dm.distance = Float(dist)

            var event = Openbikesensor_Event()
            event.distanceMeasurement = dm

            ui {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }
        }

        // CSV schreiben nur wenn Classic-Aufnahme läuft
        if recordingDeviceType == .classic, isRecording {
            let left = (effectiveLeft  == 0xFFFF) ? nil : effectiveLeft
            let right = (effectiveRight == 0xFFFF) ? nil : effectiveRight
            classicCsvRecorder?.recordMeasurement(
                leftCm: left,
                rightCm: right,
                confirmed: false,
                location: lastLocation,
                batteryVoltage: nil
            )
        }
    }

    func handleClassicButtonUpdate(_ data: Data) {
        guard let packet = parseClassicPacket(data) else { return }

        // Sensoren tauschen wenn aktiviert
        let effectiveLeft  = sensorsSwapped ? packet.rightCm : packet.leftCm
        let effectiveRight = sensorsSwapped ? packet.leftCm  : packet.rightCm

        // Debug-Log entfernt für Performance

        ui { self.handleUserInputPreview() }

        // CSV schreiben nur wenn Classic-Aufnahme läuft
        if recordingDeviceType == .classic, isRecording {
            let left = (effectiveLeft  == 0xFFFF) ? nil : effectiveLeft
            let right = (effectiveRight == 0xFFFF) ? nil : effectiveRight
            classicCsvRecorder?.recordMeasurement(
                leftCm: left,
                rightCm: right,
                confirmed: true,
                location: lastLocation,
                batteryVoltage: nil
            )
        }
    }

    private func handleClassicOffsetUpdate(_ data: Data) {
        // Offset-Daten werden aktuell nicht verwendet
    }

    private func handleClassicTrackIdUpdate(_ data: Data) {
        // Track-ID wird aktuell nicht verwendet
    }

    // -------------------------------------------------
    // MARK: - Batterie / Firmware / Hersteller
    // -------------------------------------------------

    private func handleBatteryUpdate(_ data: Data) {
        guard let level = data.first else { return }
        ui { self.batteryLevelPercent = Int(level) }
    }

    private func handleFirmwareUpdate(_ data: Data) {
        let fw = String(data: data, encoding: .utf8) ?? ""
        ui { self.firmwareRevision = fw }
    }

    private func handleManufacturerUpdate(_ data: Data) {
        let m = String(data: data, encoding: .utf8) ?? ""
        ui { self.manufacturerName = m }
    }

    // -------------------------------------------------
    // MARK: - UI / Preview-Logik
    // -------------------------------------------------

    fileprivate func updateDerivedState(from event: Openbikesensor_Event) {
        switch event.content {
        case .distanceMeasurement(let dm)?:
            let d = Double(dm.distance)
            if d > 0, d < 5 {
                lastDistanceText = String(format: "%.2f m (Sensor %d)", dm.distance, dm.sourceID)
            } else {
                lastDistanceText = "Kein gültiger Messwert empfangen (Timeout) – Sensor \(dm.sourceID)"
            }

        case .textMessage(let msg)?:
            lastMessageText = msg.text

        case .userInput(let ui)?:
            lastMessageText = "UserInput: \(ui.type)"

        case .geolocation?, .metadata?, .batteryStatus?:
            break

        case nil:
            break
        }

        switch event.content {
        case .distanceMeasurement(let dm)?:
            handleDistancePreview(dm)
        case .userInput(_)?:
            handleUserInputPreview()
        default:
            break
        }
    }

    private func handleDistancePreview(_ dm: Openbikesensor_DistanceMeasurement) {
        let rawMeters = Double(dm.distance)
        let rawCm = Int((rawMeters * 100.0).rounded())

        guard rawMeters > 0.0 else { return }

        if rawMeters >= 5.0 {
            if dm.sourceID == 1 {
                leftDistanceText = "Links (ID 1): ---"
            } else {
                rightDistanceText = "Rechts (ID \(dm.sourceID)): ---"
            }
            return
        }

        let handlebarHalf = Double(handlebarWidthCm) / 2.0
        let correctedCm = max(0, Int((Double(rawCm) - handlebarHalf).rounded()))

        // Beide Sensoren für das 5-Sekunden-Zeitfenster tracken (Portal-Kompatibilität)
        if dm.sourceID == 1 {
            timeWindowMinimum.add(correctedCm)
        } else {
            timeWindowMinimumRight.add(correctedCm)
        }

        let infoText = "Gemessen: \(rawCm) cm  |  berechnet: \(correctedCm) cm"

        if dm.sourceID == 1 {
            leftDistanceText = "Links (ID 1): \(infoText)"
            throttledSensorUpdate(leftRaw: rawCm, leftCorrected: correctedCm)
        } else {
            rightDistanceText = "Rechts (ID \(dm.sourceID)): \(infoText)"
            throttledSensorUpdate(rightRaw: rawCm, rightCorrected: correctedCm)
        }
    }

    private func handleUserInputPreview() {
        if isRecording {
            currentOvertakeCount += 1
        }

        // Portal-Kompatibilität: Bei zwei Tastendrücken innerhalb von 5 Sekunden
        // wird nur der Bereich zwischen den Tastendrücken betrachtet.
        // Falls der letzte Tastendruck länger als 5 Sekunden her ist, ignorieren wir ihn.
        let now = Date()
        let effectiveAfter: Date?
        if let last = lastButtonPressAt, now.timeIntervalSince(last) < 5.0 {
            effectiveAfter = last
        } else {
            effectiveAfter = nil
        }

        guard let minimum = timeWindowMinimum.minimum(after: effectiveAfter) else {
            overtakeDistanceText = "Überholabstand: Noch keine Messung."
            lastMinimumAtPressCm = nil
            overtakeDistanceCm = nil
            lastButtonPressAt = now  // Trotzdem setzen für nächsten Press
            return
        }

        lastMinimumAtPressCm = minimum
        overtakeDistanceCm = minimum
        overtakeDistanceText = "Überholabstand: \(minimum) cm"

        lastButtonPressAt = now  // Für nächsten Tastendruck merken
        lastOvertakeAt = Date()
        appendLiveOvertakeEvent(distanceCm: minimum)

        if isRecording, #available(iOS 16.1, *) {
            let cm = self.overtakeDistanceCm
            let active = self.sensorActiveNow
            let lastAt = self.lastSensorPacketAt

            Task { @MainActor in
                await live.update(
                    lastOvertakeCm: cm,
                    sensorActive: active,
                    lastPacketAt: lastAt,
                    recordingStartTime: self.recordingStartTime,
                    overtakeCount: self.currentOvertakeCount,
                    distanceMeters: self.currentDistanceMeters
                )
            }
        }
    }
}

// =====================================================
// MARK: - CLLocationManagerDelegate
// =====================================================

extension BluetoothManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateLocationAuthorizationStatus()
    }

    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        updateLocationAuthorizationStatus()
    }
}

// =====================================================
// MARK: - TimeWindowMinimum
// =====================================================

/// Speichert Messwerte mit Zeitstempel und berechnet das Minimum
/// der letzten `windowSeconds` Sekunden - analog zum Portal (TIME_WINDOW_SIZE = 5.0)
private struct TimeWindowMinimum {
    let windowSeconds: TimeInterval
    private var samples: [(timestamp: Date, value: Int)] = []

    init(windowSeconds: TimeInterval = 5.0) {
        self.windowSeconds = windowSeconds
    }

    mutating func add(_ value: Int) {
        let now = Date()
        samples.append((timestamp: now, value: value))
        pruneOldSamples(relativeTo: now)
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    /// Entfernt Samples, die älter als das Zeitfenster sind
    private mutating func pruneOldSamples(relativeTo now: Date) {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.timestamp < cutoff }
    }

    var hasValue: Bool {
        !samples.isEmpty
    }

    /// Liefert das Minimum aller Werte im Zeitfenster (wie Portal: min())
    var currentMinimum: Int? {
        return minimum(after: nil)
    }

    /// Liefert das Minimum aller Werte im Zeitfenster, optional nur Samples nach einem bestimmten Zeitpunkt.
    /// Portal-Kompatibilität: Bei zwei Tastendrücken innerhalb von 5 Sekunden wird nur der Bereich
    /// zwischen den Tastendrücken betrachtet.
    func minimum(after: Date?) -> Int? {
        let now = Date()
        let cutoff = now.addingTimeInterval(-windowSeconds)
        let validSamples = samples.filter { sample in
            // Sample muss innerhalb des 5-Sekunden-Fensters sein
            guard sample.timestamp >= cutoff else { return false }
            // Falls ein vorheriger Tastendruck existiert, muss Sample danach sein (strikt >)
            if let after = after {
                return sample.timestamp > after
            }
            return true
        }
        guard !validSamples.isEmpty else { return nil }
        return validSamples.map { $0.value }.min()
    }
}
