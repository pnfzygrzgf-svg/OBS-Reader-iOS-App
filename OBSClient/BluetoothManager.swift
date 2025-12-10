import Foundation
import CoreBluetooth
import SwiftProtobuf
import Combine
import CoreLocation

// MARK: - UUIDs

// OBS Lite: UART-ähnlicher Service (Protobuf-Events)
private let obsLiteServiceUUID  = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private let obsLiteCharTxUUID   = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

// OBS Classic: eigener OBS-Service mit mehreren Characteristics
private let obsClassicServiceUUID        = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000000")
private let obsClassicDistanceCharUUID   = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000002")
private let obsClassicButtonCharUUID     = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000003")
private let obsClassicOffsetCharUUID     = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000004")
private let obsClassicTrackIdCharUUID    = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000005")

// Batterie-Service
private let batteryServiceUUID           = CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")
private let batteryLevelCharUUID         = CBUUID(string: "00002A19-0000-1000-8000-00805F9B34FB")

// Device-Info-Service (Firmware, Hersteller)
private let deviceInfoServiceUUID        = CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB")
private let firmwareRevisionCharUUID     = CBUUID(string: "00002A26-0000-1000-8000-00805F9B34FB")
private let manufacturerNameCharUUID     = CBUUID(string: "00002A29-0000-1000-8000-00805F9B34FB")

// MARK: - Gerätetyp

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

// MARK: - BluetoothManager

final class BluetoothManager: NSObject, ObservableObject {

    // MARK: Published State (für SwiftUI)

    @Published var deviceType: ObsDeviceType = .lite

    @Published var isPoweredOn: Bool = false
    @Published var isConnected: Bool = false
    @Published var isRecording: Bool = false

    @Published var hasBluetoothPermission: Bool = true

    @Published var isLocationEnabled: Bool = false
    @Published var hasLocationAlwaysPermission: Bool = false

    @Published var lastEvent: Openbikesensor_Event?
    @Published var lastError: String?

    @Published var lastDistanceText: String = "Noch keine Messung. Starte eine Aufnahme, um Werte zu sehen."

    @Published var lastMessageText: String = ""

    @Published var leftDistanceText: String = "Links: Noch keine Messung."
    @Published var rightDistanceText: String = "Rechts: Noch keine Messung."
    @Published var overtakeDistanceText: String = "Überholabstand: Noch keine Messung."

    @Published var lastMedianAtPressCm: Int?

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

    @Published var currentOvertakeCount: Int = 0
    @Published var currentDistanceMeters: Double = 0

    @Published var batteryLevelPercent: Int?
    @Published var firmwareRevision: String?

    // MARK: - Private

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    private var classicDistanceChar: CBCharacteristic?
    private var classicButtonChar: CBCharacteristic?
    private var classicOffsetChar: CBCharacteristic?
    private var classicTrackIdChar: CBCharacteristic?

    private let locationManager = CLLocationManager()

    // Lite: schreibt BIN-Dateien
    private let binWriter = OBSFileWriter()
    // Classic: schreibt CSV-Dateien
    private var classicCsvRecorder: ClassicCsvRecorder?

    private var lastLocation: CLLocation?

    private var movingMedian = MovingMedian(windowSize: 3, maxSamples: 122)

    // MARK: - Init

    override init() {
        super.init()

        let stored = UserDefaults.standard.integer(forKey: "handlebarWidthCm")
        if stored != 0 {
            handlebarWidthCm = stored
        }

        if let storedType = UserDefaults.standard.string(forKey: "obsDeviceType"),
           let t = ObsDeviceType(rawValue: storedType) {
            deviceType = t
        }

        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )

        locationManager.delegate = self
        updateLocationAuthorizationStatus()
    }

    // MARK: - Recording API

    func startRecording() {
        // Zähler zurücksetzen
        DispatchQueue.main.async {
            self.currentOvertakeCount = 0
            self.currentDistanceMeters = 0
            self.lastLocation = nil
            self.isRecording = true
        }

        switch deviceType {
        case .lite:
            // BIN-Recorder (Events werden vor dem Schreiben korrigiert)
            binWriter.startSession()

        case .classic:
            // CSV-Recorder – hier wird der Handlebar-Offset bereits in den CSV-Encoder gegeben
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
    }

    func stopRecording() {
        switch deviceType {
        case .lite:
            binWriter.finishSession()

        case .classic:
            classicCsvRecorder?.finishSession()
        }

        // Statistik an Datei hängen (egal ob BIN oder CSV)
        let fileURL = (deviceType == .lite) ? binWriter.fileURL : classicCsvRecorder?.fileURL
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

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    // MARK: - GPS

    func handleLocationUpdate(_ location: CLLocation) {
        guard isRecording else { return }

        if let prev = lastLocation {
            let segment = location.distance(from: prev)
            if segment > 0, segment < 2000 {
                currentDistanceMeters += segment
            }
        }
        lastLocation = location

        // Für Lite schreiben wir Geolocation-Events ins BIN-File
        if deviceType == .lite {
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

            storeEventToBin(event)
        }
    }

    // MARK: - Location-Berechtigung

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

    private var serviceUUIDsForCurrentDevice: [CBUUID]? {
        switch deviceType {
        case .lite:
            return [obsLiteServiceUUID]
        case .classic:
            return [obsClassicServiceUUID]
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let hasPermission: Bool
        if #available(iOS 13.0, *) {
            let auth = CBCentralManager.authorization
            hasPermission = (auth == .allowedAlways)
        } else {
            hasPermission = true
        }

        DispatchQueue.main.async {
            self.hasBluetoothPermission = hasPermission
            self.isPoweredOn = (central.state == .poweredOn)
            if central.state != .poweredOn {
                self.isConnected = false
            }
        }

        guard central.state == .poweredOn, hasPermission else { return }

        UserDefaults.standard.set(deviceType.rawValue, forKey: "obsDeviceType")

        central.scanForPeripherals(
            withServices: serviceUUIDsForCurrentDevice,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        self.peripheral = peripheral
        self.peripheral?.delegate = self

        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.lastError = nil
        }

        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = error?.localizedDescription ?? "Verbindung fehlgeschlagen"
        }

        central.scanForPeripherals(
            withServices: serviceUUIDsForCurrentDevice,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            if let error = error {
                self.lastError = error.localizedDescription
            }
        }

        central.scanForPeripherals(
            withServices: serviceUUIDsForCurrentDevice,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.lastError = "Service-Fehler: \(error.localizedDescription)"
            }
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
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
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.lastError = "Char-Fehler: \(error.localizedDescription)"
            }
            return
        }

        guard let characteristics = service.characteristics else { return }

        for char in characteristics {
            switch char.uuid {
            case obsLiteCharTxUUID:
                peripheral.setNotifyValue(true, for: char)

            case obsClassicDistanceCharUUID:
                classicDistanceChar = char
                peripheral.setNotifyValue(true, for: char)

            case obsClassicButtonCharUUID:
                classicButtonChar = char
                peripheral.setNotifyValue(true, for: char)

            case obsClassicOffsetCharUUID:
                classicOffsetChar = char
                peripheral.readValue(for: char)

            case obsClassicTrackIdCharUUID:
                classicTrackIdChar = char
                peripheral.readValue(for: char)

            case batteryLevelCharUUID:
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)

            case firmwareRevisionCharUUID:
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
            DispatchQueue.main.async {
                self.lastError = "Notify-Fehler: \(error.localizedDescription)"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        if let error = error {
            DispatchQueue.main.async {
                self.lastError = "Update-Fehler: \(error.localizedDescription)"
            }
            return
        }

        guard let data = characteristic.value else { return }

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

        default:
            break
        }
    }

    // MARK: - Lite Pfad (Protobuf → BIN)

    private func handleLiteUpdate(_ data: Data) {
        print("BLE Lite chunk (\(data.count) Bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        do {
            let event = try Openbikesensor_Event(serializedData: data)
            print("Protobuf decode OK (Lite)")

            // UI bekommt das Roh-Event (ohne Lenkerkorrektur),
            // damit du dort „gemessen“ und „berechnet“ anzeigen kannst.
            DispatchQueue.main.async {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }

            // Für die BIN-Datei wird eine korrigierte Kopie geschrieben
            storeIncomingSensorEvent(event)

        } catch {
            let msg = "Protobuf-Decode-Fehler (Lite): \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.lastError = msg
            }
            print(msg)
        }
    }

    // MARK: - Classic Pfad (8-Byte-Pakete → CSV)

    private func parseClassicPacket(_ data: Data) -> (clockMs: UInt32, leftCm: UInt16, rightCm: UInt16)? {
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

    private func handleClassicDistanceUpdate(_ data: Data) {
        guard let packet = parseClassicPacket(data) else { return }

        print("BLE Classic distance (\(data.count) Bytes) clock=\(packet.clockMs) left=\(packet.leftCm)cm right=\(packet.rightCm)cm")

        // 0xFFFF = kein gültiger Wert
        let leftMeters: Double?  = (packet.leftCm  == 0xFFFF) ? nil : Double(packet.leftCm)  / 100.0
        let rightMeters: Double? = (packet.rightCm == 0xFFFF) ? nil : Double(packet.rightCm) / 100.0

        // UI + Median-Logik wie bei Lite
        if let dist = leftMeters {
            var dm = Openbikesensor_DistanceMeasurement()
            dm.sourceID = 1
            dm.distance = Float(dist)

            var event = Openbikesensor_Event()
            event.distanceMeasurement = dm

            DispatchQueue.main.async {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }

            // Classic kann theoretisch auch als „Quelle“ für Lite dienen
            if deviceType == .lite {
                storeIncomingSensorEvent(event)
            }
        }

        if let dist = rightMeters {
            var dm = Openbikesensor_DistanceMeasurement()
            dm.sourceID = 2
            dm.distance = Float(dist)

            var event = Openbikesensor_Event()
            event.distanceMeasurement = dm

            DispatchQueue.main.async {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }

            if deviceType == .lite {
                storeIncomingSensorEvent(event)
            }
        }

        // CSV schreiben (Classic)
        if deviceType == .classic, isRecording {
            let left = (packet.leftCm  == 0xFFFF) ? nil : packet.leftCm
            let right = (packet.rightCm == 0xFFFF) ? nil : packet.rightCm
            classicCsvRecorder?.recordMeasurement(
                leftCm: left,
                rightCm: right,
                confirmed: false,
                location: lastLocation,
                batteryVoltage: nil
            )
        }
    }

    private func handleClassicButtonUpdate(_ data: Data) {
        guard let packet = parseClassicPacket(data) else { return }

        print("BLE Classic button (\(data.count) Bytes) clock=\(packet.clockMs) left=\(packet.leftCm)cm right=\(packet.rightCm)cm")

        // UI-Logik: Überholvorgang zählen + Median übernehmen
        DispatchQueue.main.async {
            self.handleUserInputPreview()
        }

        // CSV: Button-Messung als „confirmed“ schreiben
        if deviceType == .classic, isRecording {
            let left = (packet.leftCm  == 0xFFFF) ? nil : packet.leftCm
            let right = (packet.rightCm == 0xFFFF) ? nil : packet.rightCm
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
        print("BLE Classic offset bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        // Optional: Könntest du hier auslesen und z. B. im UI anzeigen.
    }

    private func handleClassicTrackIdUpdate(_ data: Data) {
        if let trackId = String(data: data, encoding: .utf8) {
            print("BLE Classic trackId: \(trackId)")
        } else {
            print("BLE Classic trackId (nicht lesbar): \(data)")
        }
    }

    // MARK: - Batterie / Firmware

    private func handleBatteryUpdate(_ data: Data) {
        guard let level = data.first else { return }
        DispatchQueue.main.async {
            self.batteryLevelPercent = Int(level)
        }
        print("Battery level: \(level)%")
    }

    private func handleFirmwareUpdate(_ data: Data) {
        let fw = String(data: data, encoding: .utf8) ?? ""
        DispatchQueue.main.async {
            self.firmwareRevision = fw
        }
        print("Firmware revision: \(fw)")
    }

    // MARK: - UI / Preview-Logik

    fileprivate func updateDerivedState(from event: Openbikesensor_Event) {
        switch event.content {
        case .distanceMeasurement(let dm)?:
            let d = Double(dm.distance)

            if d > 0, d < 5 {
                lastDistanceText = String(
                    format: "%.2f m (Sensor %d)",
                    dm.distance,
                    dm.sourceID
                )
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
        // dm.distance ist hier der ROHwert (vom Sensor),
        // weil wir im UI das ursprüngliche Event verwenden (nicht die korrigierte Kopie für die BIN).
        let rawMeters = Double(dm.distance)
        let rawCm = Int((rawMeters * 100.0).rounded())

        guard rawMeters > 0.0, rawMeters < 5.0 else {
            return
        }

        let handlebarHalf = Double(handlebarWidthCm) / 2.0
        let correctedCm = max(0, Int((Double(rawCm) - handlebarHalf).rounded()))

        if dm.sourceID == 1 {
            movingMedian.add(correctedCm)
        }

        let infoText = "Gemessen: \(rawCm) cm  |  berechnet: \(correctedCm) cm"

        if dm.sourceID == 1 {
            leftRawCm = rawCm
            leftCorrectedCm = correctedCm
            leftDistanceText = "Links (ID 1): \(infoText)"
        } else {
            rightRawCm = rawCm
            rightCorrectedCm = correctedCm
            rightDistanceText = "Rechts (ID \(dm.sourceID)): \(infoText)"
        }
    }

    private func handleUserInputPreview() {
        if isRecording {
            currentOvertakeCount += 1
        }

        guard let median = movingMedian.currentMedian else {
            overtakeDistanceText = "Überholabstand: Noch keine Messung."
            lastMedianAtPressCm = nil
            overtakeDistanceCm = nil
            return
        }

        lastMedianAtPressCm = median
        overtakeDistanceCm = median
        overtakeDistanceText = "Überholabstand: \(median) cm"
    }

    // MARK: - BIN Schreiblogik (nur für Lite)

    /// Nimmt ein eingehendes Event und schreibt eine **korrigierte Kopie**
    /// in die BIN-Datei:
    /// - distanceMeasurement.distance wird um die halbe Lenkerbreite reduziert
    /// - Zeitstempel (Unix) wird angehängt
    private func storeIncomingSensorEvent(_ event: Openbikesensor_Event) {
        guard isRecording, deviceType == .lite else { return }

        var eForFile = event

        // Lenkerbreite auf alle DistanceMeasurements anwenden,
        // damit das Portal später im Zeitfenster um den Knopfdruck herum
        // bereits korrigierte Abstände sieht.
        if case .distanceMeasurement(var dm) = eForFile.content {
            let rawMeters = Double(dm.distance)
            if rawMeters > 0.0 {
                let handlebarHalfCm = Double(handlebarWidthCm) / 2.0
                let handlebarHalfMeters = handlebarHalfCm / 100.0
                let correctedMeters = max(0.0, rawMeters - handlebarHalfMeters)
                dm.distance = Float(correctedMeters)
                eForFile.distanceMeasurement = dm
            }
        }

        // Zeit-Event anhängen (Unix-Zeit)
        var t = Openbikesensor_Time()
        let now = Date().timeIntervalSince1970
        let sec = Int64(now)
        let nanos = Int32((now - Double(sec)) * 1_000_000_000)
        t.sourceID = 3
        t.seconds = sec
        t.nanoseconds = nanos
        t.reference = .unix

        eForFile.time.append(t)

        storeEventToBin(eForFile)
    }

    private func storeEventToBin(_ event: Openbikesensor_Event) {
        guard isRecording, deviceType == .lite else { return }

        do {
            let raw = try event.serializedData()
            let cobs = COBS.encode(raw)
            var frame = Data()
            frame.append(cobs)
            frame.append(0x00)
            binWriter.write(frame)
        } catch {
            print("storeEventToBin: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension BluetoothManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateLocationAuthorizationStatus()
    }

    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        updateLocationAuthorizationStatus()
    }
}

// MARK: - MovingMedian

private struct MovingMedian {
    let windowSize: Int
    let maxSamples: Int
    private var values: [Int] = []

    init(windowSize: Int, maxSamples: Int) {
        self.windowSize = max(1, windowSize)
        self.maxSamples = max(windowSize, maxSamples)
    }

    mutating func add(_ value: Int) {
        var v = values
        v.append(value)
        if v.count > maxSamples {
            v.removeFirst(v.count - maxSamples)
        }
        values = v
    }

    var hasMedian: Bool {
        values.count >= windowSize
    }

    var currentMedian: Int? {
        guard hasMedian else { return nil }
        let slice = values.suffix(windowSize)
        let sorted = slice.sorted()
        let count = sorted.count
        let mid = count / 2

        if count % 2 == 1 {
            return sorted[mid]
        } else {
            let m = Double(sorted[mid - 1] + sorted[mid]) / 2.0
            return Int(m.rounded())
        }
    }
}
