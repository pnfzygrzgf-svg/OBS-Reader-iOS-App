import Foundation
import CoreBluetooth
import SwiftProtobuf
import Combine
import CoreLocation

// UUIDs müssen mit der Firmware übereinstimmen
private let obsServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private let obsCharTxUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

final class BluetoothManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isPoweredOn: Bool = false
    @Published var isConnected: Bool = false
    @Published var isRecording: Bool = false

    /// Hat die App Bluetooth-Berechtigung (iOS-Authorization)?
    @Published var hasBluetoothPermission: Bool = true

    /// Sind Standortdienste (GPS) auf Systemebene aktiviert?
    @Published var isLocationEnabled: Bool = false

    /// Hat die App Standort-Berechtigung "Immer"?
    @Published var hasLocationAlwaysPermission: Bool = false

    @Published var lastEvent: Openbikesensor_Event?
    @Published var lastError: String?

    /// Einfacher Text mit letzter Distanz
    @Published var lastDistanceText: String = "Noch keine Messung. Starte eine Aufnahme, um Werte zu sehen."

    /// Letzte Text-/UserInput-Nachricht
    @Published var lastMessageText: String = ""

    /// Vorschau-Texte
    @Published var leftDistanceText: String = "Links: Noch keine Messung."
    @Published var rightDistanceText: String = "Rechts: Noch keine Messung."
    @Published var overtakeDistanceText: String = "Überholabstand: Noch keine Messung."

    /// Letzter Median am Button-Druck
    @Published var lastMedianAtPressCm: Int?

    /// Roh- und korrigierte Werte in cm für die beiden Sensoren (für ContentView-Anzeige)
    @Published var leftRawCm: Int?
    @Published var leftCorrectedCm: Int?

    @Published var rightRawCm: Int?
    @Published var rightCorrectedCm: Int?

    /// Letzter berechneter Überholabstand in cm (für UI-Anzeige)
    @Published var overtakeDistanceCm: Int?

    /// Lenkerbreite in cm (einstellbar im UI)
    @Published var handlebarWidthCm: Int = 60 {
        didSet {
            if handlebarWidthCm < 30 { handlebarWidthCm = 30 }
            if handlebarWidthCm > 120 { handlebarWidthCm = 120 }
            UserDefaults.standard.set(handlebarWidthCm, forKey: "handlebarWidthCm")
        }
    }

    /// Anzahl der Überholvorgänge (Tastendrücke) in der aktuellen/zuletzt beendeten Aufnahme
    @Published var currentOvertakeCount: Int = 0

    /// Aufsummierte Distanz der aktuellen/zuletzt beendeten Aufnahme (in Metern)
    @Published var currentDistanceMeters: Double = 0

    // MARK: - Private

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?

    /// Median über korrigierte Abstände (nur Sensor sourceID == 1)
    private var movingMedian = MovingMedian(windowSize: 3,
                                            maxSamples: 122)

    /// Location Manager nur zur Abfrage der Berechtigung
    private let locationManager = CLLocationManager()

    /// Writer für BIN-Datei
    private let binWriter = OBSFileWriter()

    /// Letzte GPS-Position während der Aufnahme (für Distanz-Berechnung)
    private var lastLocation: CLLocation?

    // MARK: - Init

    override init() {
        super.init()

        let stored = UserDefaults.standard.integer(forKey: "handlebarWidthCm")
        if stored != 0 {
            handlebarWidthCm = stored
        }

        // Bluetooth – System-Power-Pop-up unterdrücken
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: false
            ]
        )

        // Location-Berechtigung beobachten
        locationManager.delegate = self
        updateLocationAuthorizationStatus()
    }

    // MARK: - Recording API

    func startRecording() {
        binWriter.startSession()
        DispatchQueue.main.async {
            self.currentOvertakeCount = 0
            self.currentDistanceMeters = 0
            self.lastLocation = nil
            self.isRecording = true
        }
    }

    func stopRecording() {
        // Session beenden
        binWriter.finishSession()

        // Zähler & Distanz an die entstandene Datei "dranhängen"
        if let fileURL = binWriter.fileURL {
            let hasCount = currentOvertakeCount > 0
            let hasDistance = currentDistanceMeters > 0.0

            if hasCount || hasDistance {
                OvertakeStatsStore.store(
                    count: hasCount ? currentOvertakeCount : nil,
                    distanceMeters: hasDistance ? currentDistanceMeters : nil,
                    for: fileURL
                )
            }
        }

        DispatchQueue.main.async {
            self.isRecording = false
            // currentOvertakeCount & currentDistanceMeters bleiben stehen,
            // damit das UI sie nach dem Stoppen anzeigen kann
        }
    }

    /// vom LocationManager oder App-Code aufgerufen, um GPS-Geolocation-Events zu schreiben
    func handleLocationUpdate(_ location: CLLocation) {
        guard isRecording else { return }

        // 1) Distanz live aufsummieren
        if let prev = lastLocation {
            let segment = location.distance(from: prev) // Meter
            // einfache Plausibilitätsfilter gegen Ausreißer
            if segment > 0, segment < 2000 {
                currentDistanceMeters += segment
            }
        }
        lastLocation = location

        // 2) BIN: Geolocation-Event schreiben
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

    // MARK: - Location-Berechtigung

    private func updateLocationAuthorizationStatus() {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        // App-spezifische Berechtigung "Immer"
        let hasAlways = (status == .authorizedAlways)

        // Standortdienste (GPS) NICHT auf dem Main-Thread abfragen
        DispatchQueue.global(qos: .utility).async {
            let servicesEnabled = CLLocationManager.locationServicesEnabled()

            DispatchQueue.main.async {
                // Systemweite Standortdienste (GPS) an/aus
                self.isLocationEnabled = servicesEnabled
                // App-spezifische Berechtigung "Immer"
                self.hasLocationAlwaysPermission = hasAlways
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Berechtigung bestimmen
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

        // Ohne Power oder ohne Berechtigung: nichts scannen
        guard central.state == .poweredOn, hasPermission else { return }

        central.scanForPeripherals(
            withServices: [obsServiceUUID],
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
        peripheral.discoverServices([obsServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = error?.localizedDescription ?? "Verbindung fehlgeschlagen"
        }

        central.scanForPeripherals(
            withServices: [obsServiceUUID],
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
            withServices: [obsServiceUUID],
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
        for service in services where service.uuid == obsServiceUUID {
            peripheral.discoverCharacteristics([obsCharTxUUID], for: service)
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
        for char in characteristics where char.uuid == obsCharTxUUID {
            self.notifyCharacteristic = char
            peripheral.setNotifyValue(true, for: char)
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

        guard characteristic.uuid == obsCharTxUUID,
              let data = characteristic.value else { return }

        print("BLE chunk (\(data.count) Bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        do {
            let event = try Openbikesensor_Event(serializedData: data)
            print("Protobuf decode OK")

            // UI / Vorschau
            DispatchQueue.main.async {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }

            // Event in BIN aufnehmen
            storeIncomingSensorEvent(event)

        } catch {
            let msg = "Protobuf-Decode-Fehler: \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.lastError = msg
            }
            print(msg)
        }
    }

    // MARK: - UI / Preview-Logik

    fileprivate func updateDerivedState(from event: Openbikesensor_Event) {
        // Anzeige / Preview
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

        // Preview-Logik
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

        guard rawMeters > 0.0, rawMeters < 5.0 else {
            // 99m/Timeout nicht in der Preview verwenden
            return
        }

        let handlebarHalf = Double(handlebarWidthCm) / 2.0
        let correctedCm = max(0, Int((Double(rawCm) - handlebarHalf).rounded()))

        if dm.sourceID == 1 {
            movingMedian.add(correctedCm)
        }

        let infoText = "Gemessen: \(rawCm) cm  |  berechnet: \(correctedCm) cm"

        if dm.sourceID == 1 {
            // Links
            leftRawCm = rawCm
            leftCorrectedCm = correctedCm
            leftDistanceText = "Links (ID 1): \(infoText)"
        } else {
            // Rechts
            rightRawCm = rawCm
            rightCorrectedCm = correctedCm
            rightDistanceText = "Rechts (ID \(dm.sourceID)): \(infoText)"
        }
    }

    private func handleUserInputPreview() {
        // Jeder UserInput während der Aufnahme = ein Überholvorgang
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

    // MARK: - BIN Schreiblogik

    private func storeIncomingSensorEvent(_ event: Openbikesensor_Event) {
        guard isRecording else { return }

        var e = event

        var t = Openbikesensor_Time()
        let now = Date().timeIntervalSince1970
        let sec = Int64(now)
        let nanos = Int32((now - Double(sec)) * 1_000_000_000)
        t.sourceID = 3
        t.seconds = sec
        t.nanoseconds = nanos
        t.reference = .unix

        e.time.append(t)

        storeEventToBin(e)
    }

    private func storeEventToBin(_ event: Openbikesensor_Event) {
        guard isRecording else { return }

        do {
            let raw = try event.serializedData()
            let cobs = COBS.encode(raw)
            var frame = Data()
            frame.append(cobs)
            frame.append(0x00) // Frame-Delimiter

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

    // iOS < 14
    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        updateLocationAuthorizationStatus()
    }
}

// MARK: - MovingMedian (vereinfachte Swift-Version)

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
