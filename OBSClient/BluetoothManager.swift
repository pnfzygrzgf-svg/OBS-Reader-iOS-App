import Foundation
import CoreBluetooth
import SwiftProtobuf
import Combine
import CoreLocation

// =====================================================
// MARK: - BLE UUIDs
// =====================================================
// In BLE wird über Services & Characteristics kommuniziert.
// UUIDs identifizieren eindeutig, welche Services/Chars erwartet wird

// OBS Lite: UART-ähnlicher Service (Events kommen als Protobuf-Pakete “TX”)
private let obsLiteServiceUUID  = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private let obsLiteCharTxUUID   = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

// OBS Classic: eigener Service mit mehreren Characteristics (Distance, Button, Offset, TrackId)
private let obsClassicServiceUUID        = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000000")
private let obsClassicDistanceCharUUID   = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000002")
private let obsClassicButtonCharUUID     = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000003")
private let obsClassicOffsetCharUUID     = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000004")
private let obsClassicTrackIdCharUUID    = CBUUID(string: "1FE7FAF9-CE63-4236-0004-000000000005")

// Standard BLE Battery Service (0x180F) & Battery Level Char (0x2A19)
private let batteryServiceUUID           = CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")
private let batteryLevelCharUUID         = CBUUID(string: "00002A19-0000-1000-8000-00805F9B34FB")

// Standard BLE Device Information Service (0x180A): Firmware Revision & Manufacturer
private let deviceInfoServiceUUID        = CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB")
private let firmwareRevisionCharUUID     = CBUUID(string: "00002A26-0000-1000-8000-00805F9B34FB")
private let manufacturerNameCharUUID     = CBUUID(string: "00002A29-0000-1000-8000-00805F9B34FB")

// =====================================================
// MARK: - Gerätetyp
// =====================================================
// Unterstützung von 2 unterschiedlichen BLE-“Protokollen”/Geräten:
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
// Zentrale “Orchestrierung”:
// - BLE Scannen/Verbinden
// - Services/Characteristics entdecken
// - Notifications/Read-Updates verarbeiten
// - UI State (SwiftUI @Published) aktualisieren
// - Recording: Lite => BIN, Classic => CSV
final class BluetoothManager: NSObject, ObservableObject {

    // -------------------------------------------------
    // MARK: Published State (SwiftUI)
    // -------------------------------------------------
    // Alles hier wird von SwiftUI Views beobachtet.

    /// Gewählter Gerätetyp (Lite/Classic). Wird persistiert & löst Re-Scan aus.
    @Published var deviceType: ObsDeviceType = .lite {
        didSet {
            UserDefaults.standard.set(deviceType.rawValue, forKey: "obsDeviceType")
            restartScanForCurrentDeviceType()
        }
    }

    /// BLE-Adapter ist an (poweredOn)?
    @Published var isPoweredOn: Bool = false

    /// Aktuell verbunden?
    @Published var isConnected: Bool = false

    /// Aufnahme läuft?
    @Published var isRecording: Bool = false

    /// iOS BLE-Berechtigung vorhanden?
    @Published var hasBluetoothPermission: Bool = true

    /// Location-Services grundsätzlich aktiv?
    @Published var isLocationEnabled: Bool = false

    /// Always-Location Permission vorhanden? (für Logging sinnvoll)
    @Published var hasLocationAlwaysPermission: Bool = false

    /// Letztes Protobuf-Event (für Debug/UI)
    @Published var lastEvent: Openbikesensor_Event?

    /// Letzte Fehlermeldung, z. B. Decode/Service/Char Fehler
    @Published var lastError: String?

    /// “Human readable” UI Texte
    @Published var lastDistanceText: String = "Noch keine Messung. Starte eine Aufnahme, um Werte zu sehen."
    @Published var lastMessageText: String = ""

    @Published var leftDistanceText: String = "Links: Noch keine Messung."
    @Published var rightDistanceText: String = "Rechts: Noch keine Messung."
    @Published var overtakeDistanceText: String = "Überholabstand: Noch keine Messung."

    /// Median beim Button-Press (wird als Überholabstand genutzt)
    @Published var lastMedianAtPressCm: Int?

    /// Roh- & korrigierte Werte (Lenkerbreite wird abgezogen)
    @Published var leftRawCm: Int?
    @Published var leftCorrectedCm: Int?

    @Published var rightRawCm: Int?
    @Published var rightCorrectedCm: Int?

    @Published var overtakeDistanceCm: Int?

    /// Lenkerbreite in cm (UI Einstellung). Wird in UserDefaults gespeichert.
    /// Korrektur: gemessener Abstand minus halbe Lenkerbreite.
    @Published var handlebarWidthCm: Int = 60 {
        didSet {
            // einfache Plausibilisierung, damit keine absurden Werte passieren
            if handlebarWidthCm < 30 { handlebarWidthCm = 30 }
            if handlebarWidthCm > 120 { handlebarWidthCm = 120 }
            UserDefaults.standard.set(handlebarWidthCm, forKey: "handlebarWidthCm")
        }
    }

    /// Laufende Session-Statistiken
    @Published var currentOvertakeCount: Int = 0
    @Published var currentDistanceMeters: Double = 0

    /// Diagnose/Info aus BLE
    @Published var batteryLevelPercent: Int?
    @Published var firmwareRevision: String?
    @Published var manufacturerName: String?

    // Identität / Diagnose (Name, RSSI, vermuteter Typ etc.)
    @Published var connectedName: String = "-"
    @Published var connectedLocalName: String = "-"
    @Published var connectedId: String = "-"
    @Published var connectedRSSI: Int?
    @Published var detectedDeviceType: ObsDeviceType?
    @Published var lastBleSource: String = "-"

    // -------------------------------------------------
    // MARK: Private BLE State
    // -------------------------------------------------
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    // Classic Characteristics (für Notify/Read)
    private var classicDistanceChar: CBCharacteristic?
    private var classicButtonChar: CBCharacteristic?
    private var classicOffsetChar: CBCharacteristic?
    private var classicTrackIdChar: CBCharacteristic?

    // Location für Distanzakkumulation & optionales BIN-Geo-Event
    private let locationManager = CLLocationManager()

    // Writer/Recorder je nach DeviceType
    private let binWriter = OBSFileWriter()
    private var classicCsvRecorder: ClassicCsvRecorder?

    // Für Wegstreckenberechnung zwischen GPS Fixes
    private var lastLocation: CLLocation?

    // Median-Filter (z. B. “3er Median” zur Robustheit gegen Ausreißer)
    private var movingMedian = MovingMedian(windowSize: 3, maxSamples: 122)

    // -------------------------------------------------
    // MARK: Scan Robustness
    // -------------------------------------------------
    // Manche Geräte advertis(en) den Service nicht zuverlässig.
    // Daher: zuerst “strict” Scan nach Service UUID, danach fallback “broad” Scan,
    // nach Name filtern und nach Connect “Services verifizieren”.
    private enum ScanMode {
        case strictService
        case broadFallback
    }

    private var scanMode: ScanMode = .strictService
    private var scanFallbackTimer: Timer?

    // -------------------------------------------------
    // MARK: Init
    // -------------------------------------------------
    override init() {
        super.init()

        // Persistierte UI Settings laden
        let stored = UserDefaults.standard.integer(forKey: "handlebarWidthCm")
        if stored != 0 { handlebarWidthCm = stored }

        // Persistierten Gerätetyp laden
        if let storedType = UserDefaults.standard.string(forKey: "obsDeviceType"),
           let t = ObsDeviceType(rawValue: storedType) {
            deviceType = t
        }

        // Central Manager initialisieren (Callbacks über Delegate)
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )

        // Location Manager initialisieren
        locationManager.delegate = self
        updateLocationAuthorizationStatus()
    }

    // -------------------------------------------------
    // MARK: Recording API
    // -------------------------------------------------
    // Start/Stop steuert nur “Datei-Sessions”, BLE läuft unabhängig weiter.
    // Lite: BIN File, Classic: CSV.
    func startRecording() {
        // UI/State reset (auf Main Thread, da @Published)
        DispatchQueue.main.async {
            self.currentOvertakeCount = 0
            self.currentDistanceMeters = 0
            self.lastLocation = nil
            self.isRecording = true
        }

        switch deviceType {
        case .lite:
            // Lite schreibt Protobuf Events als COBS-geframed BIN
            binWriter.startSession()

        case .classic:
            // Classic schreibt CSV; “handlebarOffsetCm” wird für Korrektur genutzt
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
        // Writer/Recorder finalisieren
        switch deviceType {
        case .lite:
            binWriter.finishSession()
        case .classic:
            classicCsvRecorder?.finishSession()
        }

        // Optional: Stats zu Datei persistieren (wenn überhaupt Werte vorhanden sind)
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

    // -------------------------------------------------
    // MARK: GPS
    // -------------------------------------------------
    // - Summiert Wegstrecke
    // - Bei Lite: schreibt Geolocation als Event in BIN
    func handleLocationUpdate(_ location: CLLocation) {
        guard isRecording else { return }

        // Distanz zwischen letztem und aktuellem Fix addieren (ausreißerbegrenzen)
        if let prev = lastLocation {
            let segment = location.distance(from: prev)
            if segment > 0, segment < 2000 {
                currentDistanceMeters += segment
            }
        }
        lastLocation = location

        // Lite-Format: Geolocation in Protobuf Event schreiben
        if deviceType == .lite {
            var geo = Openbikesensor_Geolocation()
            geo.latitude = location.coordinate.latitude
            geo.longitude = location.coordinate.longitude
            geo.altitude = location.altitude
            geo.groundSpeed = Float(max(location.speed, 0))
            geo.hdop = Float(location.horizontalAccuracy)

            // Zeitstempel aus CLLocation.timestamp in Sekunden + Nanosekunden
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

    // -------------------------------------------------
    // MARK: Location-Berechtigung
    // -------------------------------------------------
    // Liest den aktuellen Authorization-Status aus und spiegelt ihn in @Published.
    private func updateLocationAuthorizationStatus() {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        let hasAlways = (status == .authorizedAlways)

        // locationServicesEnabled() kann etwas “teurer” sein → background thread,
        // UI Updates dann wieder auf main.
        DispatchQueue.global(qos: .utility).async {
            let servicesEnabled = CLLocationManager.locationServicesEnabled()
            DispatchQueue.main.async {
                self.isLocationEnabled = servicesEnabled
                self.hasLocationAlwaysPermission = hasAlways
            }
        }
    }

    // -------------------------------------------------
    // MARK: Scan Steuerung (robust)
    // -------------------------------------------------
    // Scan-Strategie:
    // 1) Strict: scanForPeripherals(withServices: [UUID]) → schnell & präzise
    // 2) Nach 6s ohne Erfolg: Broad: scanForPeripherals(withServices: nil),
    //    dann Kandidaten nach Namen filtern und nach Connect Services verifizieren.
    private func restartScanForCurrentDeviceType() {
        guard let central = central, isPoweredOn, hasBluetoothPermission else { return }

        // sauber disconnecten
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
            peripheral = nil
            DispatchQueue.main.async { self.isConnected = false }
        }

        stopScan()
        startStrictScanWithFallback()
    }

    private func stopScan() {
        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
        central?.stopScan()
    }

    private func startStrictScanWithFallback() {
        guard let central = central else { return }
        guard isPoweredOn, hasBluetoothPermission else { return }

        scanMode = .strictService

        // Je nach DeviceType nur den passenden Service scannen
        let services: [CBUUID] = (deviceType == .classic) ? [obsClassicServiceUUID] : [obsLiteServiceUUID]
        print("Starting STRICT scan for \(deviceType) services=\(services.map{$0.uuidString})")

        central.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Fallback nach kurzer Zeit, falls Service nicht advertised wird
        scanFallbackTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            // nur fallbacken, wenn wir wirklich noch kein Gerät haben
            guard self.peripheral == nil, self.isConnected == false else { return }
            self.startBroadFallbackScan()
        }
    }

    private func startBroadFallbackScan() {
        guard let central = central else { return }
        guard isPoweredOn, hasBluetoothPermission else { return }

        stopScan()
        scanMode = .broadFallback

        print("Starting BROAD fallback scan for \(deviceType) (connect-then-verify)")

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

// =====================================================
// MARK: - CBCentralManagerDelegate
// =====================================================
// Central events: State changes, Discoveries, Connect/Disconnect.
extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // iOS 13+: Authorization für Bluetooth separat abfragbar
        let hasPermission: Bool
        if #available(iOS 13.0, *) {
            let auth = CBCentralManager.authorization
            hasPermission = (auth == .allowedAlways)
        } else {
            hasPermission = true
        }

        // UI State updaten
        DispatchQueue.main.async {
            self.hasBluetoothPermission = hasPermission
            self.isPoweredOn = (central.state == .poweredOn)
            if central.state != .poweredOn {
                self.isConnected = false
            }
        }

        print("centralManagerDidUpdateState: state=\(central.state.rawValue) perm=\(hasPermission)")

        // Nur scannen, wenn BLE an + Permission ok
        guard central.state == .poweredOn, hasPermission else { return }
        startStrictScanWithFallback()
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        // Advertisements: localName, serviceUUIDs, connectable, etc.
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "-"
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true

        print(">> didDiscover: \(peripheral.name ?? "unknown") rssi=\(RSSI) localName=\(localName) connectable=\(isConnectable) services=\(serviceUUIDs.map{$0.uuidString}) mode=\(scanMode)")

        // Wenn wir bereits eine Verbindung starten, keine weiteren Kandidaten
        if self.peripheral != nil { return }
        if !isConnectable { return }

        let name = (peripheral.name ?? "").lowercased()
        let ln = localName.lowercased()

        switch scanMode {
        case .strictService:
            // STRICT ist bereits per withServices gefiltert, aber Safety-Net:
            if deviceType == .classic {
                if !serviceUUIDs.isEmpty, !serviceUUIDs.contains(obsClassicServiceUUID) { return }
            } else {
                if !serviceUUIDs.isEmpty, !serviceUUIDs.contains(obsLiteServiceUUID) { return }
            }

        case .broadFallback:
            // BROAD: nur Kandidaten, die “nach OBS aussehen”
            // Finale Entscheidung treffen wir nach dem Connect via Service-Verify.
            let looksObs = name.contains("obs")
            || ln.contains("obs")
            || ln.contains("openbikesensor")
            || name.contains("openbikesensor")
            if !looksObs { return }
        }

        // Kandidat für UI merken (Diagnose)
        DispatchQueue.main.async {
            self.connectedName = peripheral.name ?? "-"
            self.connectedLocalName = localName
            self.connectedId = peripheral.identifier.uuidString
            self.connectedRSSI = RSSI.intValue
            self.detectedDeviceType = nil
            self.lastBleSource = "-"
        }

        // Verbinden: Peripheral merken & Delegate setzen
        self.peripheral = peripheral
        self.peripheral?.delegate = self

        // Scan stoppen, um nicht parallel zig Geräte zu verbinden
        stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        print(">> didConnect \(peripheral.identifier)")

        DispatchQueue.main.async {
            self.isConnected = true
            self.lastError = nil
            self.connectedName = peripheral.name ?? self.connectedName
            self.connectedId = peripheral.identifier.uuidString
        }

        // Nach dem Connect: Services entdecken (nil => alle)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print(">> didFailToConnect: \(error?.localizedDescription ?? "unknown error")")

        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = error?.localizedDescription ?? "Verbindung fehlgeschlagen"
        }

        // Reset & neu scannen
        self.peripheral = nil
        startStrictScanWithFallback()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print(">> didDisconnect \(peripheral.identifier) error=\(String(describing: error))")

        DispatchQueue.main.async {
            self.isConnected = false
            if let error = error {
                self.lastError = error.localizedDescription
            }
            self.detectedDeviceType = nil
            self.lastBleSource = "-"
        }

        // Reset & neu scannen
        self.peripheral = nil
        startStrictScanWithFallback()
    }
}

// =====================================================
// MARK: - CBPeripheralDelegate
// =====================================================
// Peripheral events: Services/Characteristics discovery, notifications, value updates.
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

        // ---- Service-Verify ----
        // Hier prüfen wir endgültig, ob es wirklich Classic oder Lite ist.
        let uuids = Set(services.map { $0.uuid })
        let hasClassic = uuids.contains(obsClassicServiceUUID)
        let hasLite = uuids.contains(obsLiteServiceUUID)

        DispatchQueue.main.async {
            if hasClassic { self.detectedDeviceType = .classic }
            else if hasLite { self.detectedDeviceType = .lite }
            else { self.detectedDeviceType = nil }
        }

        // Wenn wir das falsche Gerät erwischt haben: disconnect + weiter scannen
        if deviceType == .classic, !hasClassic {
            DispatchQueue.main.async {
                self.lastError = "Falsches Gerät verbunden (kein OBS Classic Service)."
            }
            central?.cancelPeripheralConnection(peripheral)
            return
        }

        if deviceType == .lite, !hasLite {
            DispatchQueue.main.async {
                self.lastError = "Falsches Gerät verbunden (kein OBS Lite Service)."
            }
            central?.cancelPeripheralConnection(peripheral)
            return
        }

        // Services sind ok → passende Characteristics entdecken
        for service in services {
            print(">> discovered service \(service.uuid)")

            switch service.uuid {
            case obsLiteServiceUUID:
                // Lite: wir brauchen TX Notifications (Protobuf)
                peripheral.discoverCharacteristics([obsLiteCharTxUUID], for: service)

            case obsClassicServiceUUID:
                // Classic: mehrere Characteristics
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

        print(">> discovered chars for service \(service.uuid)")
        for char in characteristics {
            print("   char \(char.uuid)")

            switch char.uuid {
            case obsLiteCharTxUUID:
                // Notifications aktivieren: wir bekommen didUpdateValueFor bei neuen Paketen
                peripheral.setNotifyValue(true, for: char)

            case obsClassicDistanceCharUUID:
                classicDistanceChar = char
                peripheral.setNotifyValue(true, for: char)

            case obsClassicButtonCharUUID:
                classicButtonChar = char
                peripheral.setNotifyValue(true, for: char)

            case obsClassicOffsetCharUUID:
                // Offset wird gelesen (keine Notification nötig, außer Device sendet so)
                classicOffsetChar = char
                peripheral.readValue(for: char)

            case obsClassicTrackIdCharUUID:
                classicTrackIdChar = char
                peripheral.readValue(for: char)

            case batteryLevelCharUUID:
                // Battery Level: notify + initial read
                peripheral.setNotifyValue(true, for: char)
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
            DispatchQueue.main.async {
                self.lastError = "Notify-Fehler: \(error.localizedDescription)"
            }
        } else {
            print(">> notify state updated for \(characteristic.uuid), isNotifying=\(characteristic.isNotifying)")
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

        // Für UI/Debug: merken, welche Quelle zuletzt etwas geliefert hat
        DispatchQueue.main.async {
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

        // Routing nach Characteristic
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
    // MARK: - Lite Pfad (Protobuf → BIN)
    // -------------------------------------------------
    // Lite sendet komplette Protobuf Events als Datenpakete.
    private func handleLiteUpdate(_ data: Data) {
        // Hexdump hilft beim Debugging (z. B. wenn Decode fehlschlägt)
        print("BLE Lite chunk (\(data.count) Bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        do {
            // Protobuf decode: Data -> Openbikesensor_Event
            let event = try Openbikesensor_Event(serializedData: data)
            print("Protobuf decode OK (Lite)")

            // UI aktualisieren (SwiftUI State)
            DispatchQueue.main.async {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }

            // Wenn recording aktiv: Event in BIN schreiben
            storeIncomingSensorEvent(event)

        } catch {
            let msg = "Protobuf-Decode-Fehler (Lite): \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.lastError = msg
            }
            print(msg)
        }
    }

    // -------------------------------------------------
    // MARK: - Classic Pfad (8-Byte-Pakete → CSV)
    // -------------------------------------------------
    // Classic sendet 8 Byte:
    // [0..3] clockMs (UInt32 little endian)
    // [4..5] leftCm  (UInt16 little endian)
    // [6..7] rightCm (UInt16 little endian)
    // 0xFFFF bedeutet “kein gültiger Wert”.
    func parseClassicPacket(_ data: Data) -> (clockMs: UInt32, leftCm: UInt16, rightCm: UInt16)? {
        guard data.count == 8 else { return nil }
        let bytes = [UInt8](data)

        // Little-Endian zusammensetzen
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

        print("BLE Classic distance (\(data.count) Bytes) clock=\(packet.clockMs) left=\(packet.leftCm)cm right=\(packet.rightCm)cm")

        // 0xFFFF => nil; ansonsten cm -> meter
        let leftMeters: Double?  = (packet.leftCm  == 0xFFFF) ? nil : Double(packet.leftCm)  / 100.0
        let rightMeters: Double? = (packet.rightCm == 0xFFFF) ? nil : Double(packet.rightCm) / 100.0

        // Für UI/Preview bauen wir Events “wie Lite” nach,
        // damit updateDerivedState & Preview-Logik wiederverwendet werden kann.
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

            // (Optional) Wenn jemand Classic-Daten trotzdem ins BIN schreiben möchte:
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

        // Classic: Während Recording CSV schreiben (Rohwerte in cm + confirmed=false)
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

    func handleClassicButtonUpdate(_ data: Data) {
        guard let packet = parseClassicPacket(data) else { return }

        print("BLE Classic button (\(data.count) Bytes) clock=\(packet.clockMs) left=\(packet.leftCm)cm right=\(packet.rightCm)cm")

        // Button bedeutet “Überholvorgang markieren” → Median übernehmen & counter erhöhen
        DispatchQueue.main.async {
            self.handleUserInputPreview()
        }

        // Classic: confirmed=true
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
        // Offset/Calibration Info (derzeit nur Debug-Ausgabe)
        print("BLE Classic offset bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }

    private func handleClassicTrackIdUpdate(_ data: Data) {
        // TrackId ist üblicherweise UTF-8 Text
        if let trackId = String(data: data, encoding: .utf8) {
            print("BLE Classic trackId: \(trackId)")
        } else {
            print("BLE Classic trackId (nicht lesbar): \(data)")
        }
    }

    // -------------------------------------------------
    // MARK: - Batterie / Firmware / Hersteller
    // -------------------------------------------------
    private func handleBatteryUpdate(_ data: Data) {
        // Battery Level ist 1 Byte: 0..100
        guard let level = data.first else { return }
        DispatchQueue.main.async { self.batteryLevelPercent = Int(level) }
        print("Battery level: \(level)%")
    }

    private func handleFirmwareUpdate(_ data: Data) {
        // Firmware Revision kommt i. d. R. als UTF-8 String
        let fw = String(data: data, encoding: .utf8) ?? ""
        DispatchQueue.main.async { self.firmwareRevision = fw }
        print("Firmware revision: \(fw)")
    }

    private func handleManufacturerUpdate(_ data: Data) {
        let m = String(data: data, encoding: .utf8) ?? ""
        DispatchQueue.main.async { self.manufacturerName = m }
        print("Manufacturer name: \(m)")
    }

    // -------------------------------------------------
    // MARK: - UI / Preview-Logik
    // -------------------------------------------------
    // Vereinheitlicht die Darstellung für Lite & Classic:
    // nimmt ein Event und baut die UI Texte + derived Values.
    fileprivate func updateDerivedState(from event: Openbikesensor_Event) {
        // Grobe Textausgabe je nach Event-Typ
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

        // Detail-Handling für bestimmte Typen
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
        // Protobuf liefert Meter; UI will cm.
        let rawMeters = Double(dm.distance)
        let rawCm = Int((rawMeters * 100.0).rounded())

        // Plausibilitätsfenster: 0..5m
        guard rawMeters > 0.0, rawMeters < 5.0 else { return }

        // Korrektur: Lenker steht schon im Raum → halbe Lenkerbreite abziehen
        let handlebarHalf = Double(handlebarWidthCm) / 2.0
        let correctedCm = max(0, Int((Double(rawCm) - handlebarHalf).rounded()))

        // Median nur für “links” (sourceID 1) sammeln, weil Button i. d. R. auf linker Messung basiert
        if dm.sourceID == 1 {
            movingMedian.add(correctedCm)
        }

        let infoText = "Gemessen: \(rawCm) cm  |  berechnet: \(correctedCm) cm"

        // Quelle bestimmen: links/rechts
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
        // Button press zählt als Überholvorgang, wenn Recording aktiv ist
        if isRecording {
            currentOvertakeCount += 1
        }

        // Median nur anzeigen, wenn genug Samples vorhanden
        guard let median = movingMedian.currentMedian else {
            overtakeDistanceText = "Überholabstand: Noch keine Messung."
            lastMedianAtPressCm = nil
            overtakeDistanceCm = nil
            return
        }

        // Median beim Button-Press “einfrieren”
        lastMedianAtPressCm = median
        overtakeDistanceCm = median
        overtakeDistanceText = "Überholabstand: \(median) cm"
    }

    // -------------------------------------------------
    // MARK: - BIN Schreiblogik (nur für Lite)
    // -------------------------------------------------
    // Bei Lite speichern wir Events in eine BIN-Datei:
    // - optional Distance-Korrektur (Lenkerbreite)
    // - Timestamp anhängen
    // - Protobuf serialisieren
    // - COBS framing + 0x00 Terminator
    private func storeIncomingSensorEvent(_ event: Openbikesensor_Event) {
        guard isRecording, deviceType == .lite else { return }

        var eForFile = event

        // Distance-Korrektur direkt in das Event schreiben (nur, wenn es ein DistanceMeasurement ist)
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

        // Timestamp aus “jetzt” erzeugen (Unix + nanos)
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
            // Protobuf serialisieren
            let raw = try event.serializedData()

            // COBS: macht “0x00” frei, damit wir 0x00 als Frame-Terminator nutzen können
            let cobs = COBS.encode(raw)

            // Frame = cobs(payload) + 0x00
            var frame = Data()
            frame.append(cobs)
            frame.append(0x00)

            // In Datei schreiben
            binWriter.write(frame)
        } catch {
            print("storeEventToBin: \(error)")
        }
    }
}

// =====================================================
// MARK: - CLLocationManagerDelegate
// =====================================================
// Reagiert auf Authorization-Änderungen.
// (Location Updates selbst kommen i. d. R. in didUpdateLocations – nicht enthalten,
// weil du wahrscheinlich woanders die Updates weiterleitest.)
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
// MARK: - MovingMedian
// =====================================================
// Kleiner Helfer: “moving median” über ein Fenster (windowSize).
// - values speichert die letzten maxSamples
// - currentMedian berechnet Median über das suffix(windowSize)
private struct MovingMedian {
    let windowSize: Int
    let maxSamples: Int
    private var values: [Int] = []

    init(windowSize: Int, maxSamples: Int) {
        self.windowSize = max(1, windowSize)
        self.maxSamples = max(windowSize, maxSamples)
    }

    mutating func add(_ value: Int) {
        // Kopie + append, dann auf maxSamples begrenzen
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

        // Median: ungerade => mittleres Element, gerade => Mittelwert der zwei mittleren
        if count % 2 == 1 {
            return sorted[mid]
        } else {
            let m = Double(sorted[mid - 1] + sorted[mid]) / 2.0
            return Int(m.rounded())
        }
    }
}
