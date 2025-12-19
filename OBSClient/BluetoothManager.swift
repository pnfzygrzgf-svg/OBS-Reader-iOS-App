import Foundation
import CoreBluetooth
import SwiftProtobuf
import Combine
import CoreLocation

// =====================================================
// MARK: - BLE UUIDs
// =====================================================
// UUIDs der BLE-Services/Characteristics, die das OBS Lite / OBS Classic Gerät anbietet.
// Diese werden beim Scannen, Verbinden und beim Abonnieren von Notifications verwendet.

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
// MARK: - Gerätetyp
// =====================================================
// Steuert den "Datenpfad":
// - Lite: Protobuf-Events kommen als BLE Notify rein und werden als BIN gespeichert.
// - Classic: 8-Byte Pakete kommen rein und werden (bei Aufnahme) als CSV gespeichert.

enum ObsDeviceType: String, CaseIterable, Identifiable {
    case lite
    case classic

    var id: String { rawValue }

    /// Anzeigename für die UI.
    var displayName: String {
        switch self {
        case .lite:    return "OBS Lite"
        case .classic: return "OBS Classic"
        }
    }

    /// Kurzbeschreibung, wofür der Gerätetyp steht (z.B. in Settings).
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
// Zentrale Klasse für:
// - Bluetooth Scan/Connect/Subscribe (CoreBluetooth)
// - UI-State (SwiftUI via @Published)
// - Aufnahme-Logik (BIN/CSV)
// - GPS Distanzzählung und Geolocation-Events (nur Lite)

final class BluetoothManager: NSObject, ObservableObject {

    // -------------------------------------------------
    // MARK: Published State (SwiftUI)
    // -------------------------------------------------
    // Diese Properties werden von SwiftUI beobachtet und aktualisieren die UI automatisch.

    /// Ausgewählter Gerätetyp (Lite/Classic). Bei Änderung wird gespeichert und Scan neu gestartet.
    @Published var deviceType: ObsDeviceType = .lite {
        didSet {
            UserDefaults.standard.set(deviceType.rawValue, forKey: "obsDeviceType")
            restartScanForCurrentDeviceType()
        }
    }

    /// Systemzustand von Bluetooth (poweredOn?) und Verbindungsstatus.
    @Published var isPoweredOn: Bool = false
    @Published var isConnected: Bool = false

    /// Ob aktuell eine Aufnahme läuft (wir schreiben Daten in BIN/CSV).
    @Published var isRecording: Bool = false

    /// CoreBluetooth-Berechtigung (iOS 13+ kann "not allowed" sein).
    @Published var hasBluetoothPermission: Bool = true

    /// Location/GPS Status + Berechtigungen (für Distanz und Geolocation Events).
    @Published var isLocationEnabled: Bool = false
    @Published var hasLocationAlwaysPermission: Bool = false

    /// Letztes empfangenes Protobuf-Event und Fehlertext (Debug/Statusanzeige).
    @Published var lastEvent: Openbikesensor_Event?
    @Published var lastError: String?

    /// Texte für UI-Ausgabe (Messwerte/Status).
    @Published var lastDistanceText: String = "Noch keine Messung. Starte eine Aufnahme, um Werte zu sehen."
    @Published var lastMessageText: String = ""

    @Published var leftDistanceText: String = "Links: Noch keine Messung."
    @Published var rightDistanceText: String = "Rechts: Noch keine Messung."
    @Published var overtakeDistanceText: String = "Überholabstand: Noch keine Messung."

    /// Medianwert (cm) zum Zeitpunkt des Button-Press (für "Überholabstand").
    @Published var lastMedianAtPressCm: Int?

    /// Roh- und korrigierte Distanz (cm) je Seite (für UI/Debug).
    @Published var leftRawCm: Int?
    @Published var leftCorrectedCm: Int?

    @Published var rightRawCm: Int?
    @Published var rightCorrectedCm: Int?

    /// Ergebnisdistanz für Überholmanöver (Median, cm).
    @Published var overtakeDistanceCm: Int?

    /// Lenkerbreite (cm). Wird begrenzt und in UserDefaults gespeichert.
    /// Korrektur: Rohdistanz - (Lenkerbreite/2).
    @Published var handlebarWidthCm: Int = 60 {
        didSet {
            if handlebarWidthCm < 30 { handlebarWidthCm = 30 }
            if handlebarWidthCm > 120 { handlebarWidthCm = 120 }
            UserDefaults.standard.set(handlebarWidthCm, forKey: "handlebarWidthCm")
        }
    }

    /// Laufende Statistik während einer Aufnahme.
    @Published var currentOvertakeCount: Int = 0
    @Published var currentDistanceMeters: Double = 0

    /// Geräteinfos, falls per BLE gelesen.
    @Published var batteryLevelPercent: Int?
    @Published var firmwareRevision: String?
    @Published var manufacturerName: String?

    /// Anzeige des verbundenen Gerätes + Debug Infos.
    @Published var connectedName: String = "-"
    @Published var connectedLocalName: String = "-"
    @Published var connectedId: String = "-"
    @Published var connectedRSSI: Int?
    @Published var detectedDeviceType: ObsDeviceType?
    @Published var lastBleSource: String = "-"

    // -------------------------------------------------
    // MARK: Private BLE State
    // -------------------------------------------------
    // CoreBluetooth Objekte + Characteristic-Referenzen.

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    private var classicDistanceChar: CBCharacteristic?
    private var classicButtonChar: CBCharacteristic?
    private var classicOffsetChar: CBCharacteristic?
    private var classicTrackIdChar: CBCharacteristic?

    // CoreLocation Manager (liefert GPS/Location Updates und Berechtigungsstatus).
    private let locationManager = CLLocationManager()

    // Writer/Recorder für die Datei-Ausgabe.
    private let binWriter = OBSFileWriter()
    private var classicCsvRecorder: ClassicCsvRecorder?

    // Letzte GPS Position (für Distanzberechnung über Segmente).
    private var lastLocation: CLLocation?

    // Gleitender Median über korrigierte Messwerte (z.B. zur Stabilisierung beim Button-Press).
    private var movingMedian = MovingMedian(windowSize: 3, maxSamples: 122)

    // -------------------------------------------------
    // MARK: Scan Robustness
    // -------------------------------------------------
    // Scan-Strategie:
    // 1) strictService: scan nur nach dem gewünschten Service (schnell/sauber)
    // 2) broadFallback: falls nichts gefunden wird: scan nach allem und filtere über Namen

    private enum ScanMode {
        case strictService
        case broadFallback
    }

    private var scanMode: ScanMode = .strictService
    private var scanFallbackTimer: Timer?

    // -------------------------------------------------
    // MARK: Init
    // -------------------------------------------------
    // Setup:
    // - gespeicherte Settings laden
    // - CBCentralManager starten
    // - LocationManager konfigurieren

    override init() {
        super.init()

        // Persistierte Lenkerbreite laden (falls vorhanden).
        let stored = UserDefaults.standard.integer(forKey: "handlebarWidthCm")
        if stored != 0 { handlebarWidthCm = stored }

        // Persistierten Gerätetyp laden (falls vorhanden).
        if let storedType = UserDefaults.standard.string(forKey: "obsDeviceType"),
           let t = ObsDeviceType(rawValue: storedType) {
            deviceType = t
        }

        // Central Manager initialisieren (ohne Power-Alert Popup).
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )

        // Location Manager vorbereiten.
        locationManager.delegate = self
        updateLocationAuthorizationStatus()
    }

    // -------------------------------------------------
    // MARK: Main-thread helper
    // -------------------------------------------------
    // Hilfsfunktion, um UI-Änderungen sicher im Main Thread zu machen.

    @inline(__always)
    private func ui(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() }
        else { DispatchQueue.main.async(execute: block) }
    }

    // -------------------------------------------------
    // MARK: Recording API
    // -------------------------------------------------
    // Start/Stop einer "Session" (Dateischreiben + Statistiken zurücksetzen).

    /// Startet eine Aufnahme:
    /// - setzt Zähler zurück
    /// - startet je nach Gerätetyp BIN-Writer oder CSV-Recorder
    func startRecording() {
        ui {
            self.currentOvertakeCount = 0
            self.currentDistanceMeters = 0
            self.lastLocation = nil
            self.isRecording = true
        }

        switch deviceType {
        case .lite:
            // Lite schreibt COBS-gerahmte Protobuf-Events in eine BIN-Datei.
            binWriter.startSession()

        case .classic:
            // Classic schreibt CSV und braucht Offset (Lenker/2) + Versionsinfos.
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

    /// Stoppt die Aufnahme:
    /// - beendet Datei-Ausgabe
    /// - schreibt ggf. zusätzliche Statistiken (Count/Distance) zur Datei
    /// - setzt isRecording auf false
    func stopRecording() {
        switch deviceType {
        case .lite:
            binWriter.finishSession()
        case .classic:
            classicCsvRecorder?.finishSession()
        }

        // Ermittelt die aktuelle Datei-URL, um Stats zu speichern.
        let fileURL = (deviceType == .lite) ? binWriter.fileURL : classicCsvRecorder?.fileURL
        if let url = fileURL {
            let hasCount = currentOvertakeCount > 0
            let hasDistance = currentDistanceMeters > 0.0

            // Speichert Zusatzdaten nur, wenn überhaupt etwas gezählt wurde.
            if hasCount || hasDistance {
                OvertakeStatsStore.store(
                    count: hasCount ? currentOvertakeCount : nil,
                    distanceMeters: hasDistance ? currentDistanceMeters : nil,
                    for: url
                )
            }
        }

        ui { self.isRecording = false }
    }

    // -------------------------------------------------
    // MARK: GPS
    // -------------------------------------------------
    // Verarbeitet neue Standortdaten:
    // - Distanz in Metern fortschreiben (Segment-Distanzen)
    // - bei Lite: Geolocation als Protobuf-Event in die BIN-Datei schreiben

    /// Wird von außen aufgerufen, wenn ein neues CLLocation-Update vorliegt.
    /// (z.B. aus einem Location-Manager Stream)
    func handleLocationUpdate(_ location: CLLocation) {
        // GPS nur relevant, wenn wir gerade aufzeichnen.
        guard isRecording else { return }

        // Distanz fortschreiben: Summe der Segmentdistanzen.
        ui {
            if let prev = self.lastLocation {
                let segment = location.distance(from: prev)
                // Filter: vermeidet GPS-Sprünge (z.B. > 2 km pro Update).
                if segment > 0, segment < 2000 {
                    self.currentDistanceMeters += segment
                }
            }
            self.lastLocation = location
        }

        // Lite: zusätzlich Geolocation-Event in die BIN-Datei schreiben.
        if deviceType == .lite {
            var geo = Openbikesensor_Geolocation()
            geo.latitude = location.coordinate.latitude
            geo.longitude = location.coordinate.longitude
            geo.altitude = location.altitude
            geo.groundSpeed = Float(max(location.speed, 0))
            geo.hdop = Float(location.horizontalAccuracy)

            // Zeitstempel als Openbikesensor_Time (Unix + Nanosekunden).
            var t = Openbikesensor_Time()
            let ts = location.timestamp.timeIntervalSince1970
            let sec = Int64(ts)
            let nanos = Int32((ts - Double(sec)) * 1_000_000_000)
            t.sourceID = 3
            t.seconds = sec
            t.nanoseconds = nanos
            t.reference = .unix

            // Event zusammenbauen und speichern.
            var event = Openbikesensor_Event()
            event.geolocation = geo
            event.time = [t]

            storeEventToBin(event)
        }
    }

    // -------------------------------------------------
    // MARK: Location-Berechtigung
    // -------------------------------------------------
    // Liest Location-Services/Berechtigung und schreibt den Status in @Published Props.

    /// Aktualisiert isLocationEnabled + hasLocationAlwaysPermission.
    /// Nutzt Hintergrundthread für locationServicesEnabled(), danach zurück in Main Thread.
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
    // MARK: Scan Steuerung (robust)
    // -------------------------------------------------
    // Kapselt Scan-Start/Stop und die Fallback-Strategie.

    /// Stoppt ggf. bestehende Verbindung, beendet Scan und startet neu passend zum deviceType.
    private func restartScanForCurrentDeviceType() {
        guard let central = central, isPoweredOn, hasBluetoothPermission else { return }

        // Falls noch verbunden/verbinden: Verbindung abbrechen, damit wir sauber neu suchen können.
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
            peripheral = nil
            ui { self.isConnected = false }
        }

        stopScan()
        startStrictScanWithFallback()
    }

    /// Stoppt Scan und deaktiviert Fallback-Timer.
    private func stopScan() {
        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
        central?.stopScan()
    }

    /// Startet "strict" Scan nur nach ServiceUUID (schnell + weniger Fehltreffer).
    /// Wenn nach 6 Sekunden kein Gerät gefunden wurde, wechselt auf broadFallback.
    private func startStrictScanWithFallback() {
        guard let central = central else { return }
        guard isPoweredOn, hasBluetoothPermission else { return }

        scanMode = .strictService

        let services: [CBUUID] = (deviceType == .classic) ? [obsClassicServiceUUID] : [obsLiteServiceUUID]
        print("Starting STRICT scan for \(deviceType) services=\(services.map{$0.uuidString})")

        central.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Falls strict scan nichts findet: broad scan starten (connect-then-verify).
        scanFallbackTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard self.peripheral == nil, self.isConnected == false else { return }
            self.startBroadFallbackScan()
        }
    }

    /// Startet breiten Scan ohne Services-Filter und filtert später anhand Name/LocalName.
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
// Events vom Central:
// - Bluetooth State Changes
// - Peripheral entdeckt
// - Verbunden / Verbindung fehlgeschlagen / getrennt

extension BluetoothManager: CBCentralManagerDelegate {

    /// Wird aufgerufen, wenn sich Bluetooth Status ändert (poweredOn/off etc.).
    /// Hier prüfen wir auch die Permission und starten den Scan sobald möglich.
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
                self.isConnected = false
            }
        }

        print("centralManagerDidUpdateState: state=\(central.state.rawValue) perm=\(hasPermission)")

        // Nur scannen, wenn Bluetooth an + Permission ok.
        guard central.state == .poweredOn, hasPermission else { return }
        startStrictScanWithFallback()
    }

    /// Wird für jedes gefundene BLE-Gerät aufgerufen (Scan Ergebnis).
    /// Hier filtern wir nach ScanMode und verbinden dann das erste passende Gerät.
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "-"
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true

        print(">> didDiscover: \(peripheral.name ?? "unknown") rssi=\(RSSI) localName=\(localName) connectable=\(isConnectable) services=\(serviceUUIDs.map{$0.uuidString}) mode=\(scanMode)")

        // Nur ein Gerät gleichzeitig verbinden.
        if self.peripheral != nil { return }
        if !isConnectable { return }

        let name = (peripheral.name ?? "").lowercased()
        let ln = localName.lowercased()

        // Filterlogik abhängig vom Scan-Modus.
        switch scanMode {
        case .strictService:
            // Im strict mode erwarten wir idealerweise den passenden Service.
            // Falls serviceUUIDs leer ist (manche Geräte), lassen wir das Gerät dennoch zu.
            if deviceType == .classic {
                if !serviceUUIDs.isEmpty, !serviceUUIDs.contains(obsClassicServiceUUID) { return }
            } else {
                if !serviceUUIDs.isEmpty, !serviceUUIDs.contains(obsLiteServiceUUID) { return }
            }

        case .broadFallback:
            // Broad scan: wir akzeptieren Geräte, die im Namen nach OBS aussehen.
            let looksObs = name.contains("obs")
            || ln.contains("obs")
            || ln.contains("openbikesensor")
            || name.contains("openbikesensor")
            if !looksObs { return }
        }

        // UI Debug Infos aktualisieren.
        ui {
            self.connectedName = peripheral.name ?? "-"
            self.connectedLocalName = localName
            self.connectedId = peripheral.identifier.uuidString
            self.connectedRSSI = RSSI.intValue
            self.detectedDeviceType = nil
            self.lastBleSource = "-"
        }

        // Peripheral merken, Delegate setzen und verbinden.
        self.peripheral = peripheral
        self.peripheral?.delegate = self

        stopScan()
        central.connect(peripheral, options: nil)
    }

    /// Erfolgreich verbunden: Services discovery starten.
    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        print(">> didConnect \(peripheral.identifier)")

        ui {
            self.isConnected = true
            self.lastError = nil
            self.connectedName = peripheral.name ?? self.connectedName
            self.connectedId = peripheral.identifier.uuidString
        }

        // nil => alle Services entdecken (inkl Battery/DeviceInfo).
        peripheral.discoverServices(nil)
    }

    /// Verbindung fehlgeschlagen: State zurücksetzen und erneut scannen.
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print(">> didFailToConnect: \(error?.localizedDescription ?? "unknown error")")

        ui {
            self.isConnected = false
            self.lastError = error?.localizedDescription ?? "Verbindung fehlgeschlagen"
        }

        self.peripheral = nil
        startStrictScanWithFallback()
    }

    /// Verbindung getrennt: State zurücksetzen und erneut scannen (Auto-Reconnect Verhalten).
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print(">> didDisconnect \(peripheral.identifier) error=\(String(describing: error))")

        ui {
            self.isConnected = false
            if let error = error {
                self.lastError = error.localizedDescription
            }
            self.detectedDeviceType = nil
            self.lastBleSource = "-"
        }

        self.peripheral = nil
        startStrictScanWithFallback()
    }
}

// =====================================================
// MARK: - CBPeripheralDelegate
// =====================================================
// Events vom Peripheral:
// - Services entdeckt
// - Characteristics entdeckt
// - Notify-State geändert
// - Value Updates (Notify oder Read)

extension BluetoothManager: CBPeripheralDelegate {

    /// Nach discoverServices(nil) kommt diese Callback.
    /// Hier:
    /// - ermitteln ob Lite/Classic Service vorhanden ist
    /// - "falsches Gerät" erkennen und ggf. disconnecten
    /// - passende Characteristics pro Service entdecken
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        if let error = error {
            ui { self.lastError = "Service-Fehler: \(error.localizedDescription)" }
            return
        }

        guard let services = peripheral.services else { return }

        // Herausfinden, welche OBS-Variante das Gerät tatsächlich hat.
        let uuids = Set(services.map { $0.uuid })
        let hasClassic = uuids.contains(obsClassicServiceUUID)
        let hasLite = uuids.contains(obsLiteServiceUUID)

        ui {
            if hasClassic { self.detectedDeviceType = .classic }
            else if hasLite { self.detectedDeviceType = .lite }
            else { self.detectedDeviceType = nil }
        }

        // Schutz: wenn User z.B. Classic ausgewählt hat, aber Lite verbunden wurde.
        if deviceType == .classic, !hasClassic {
            ui { self.lastError = "Falsches Gerät verbunden (kein OBS Classic Service)." }
            central?.cancelPeripheralConnection(peripheral)
            return
        }

        if deviceType == .lite, !hasLite {
            ui { self.lastError = "Falsches Gerät verbunden (kein OBS Lite Service)." }
            central?.cancelPeripheralConnection(peripheral)
            return
        }

        // Pro Service die benötigten Characteristics entdecken.
        for service in services {
            print(">> discovered service \(service.uuid)")

            switch service.uuid {
            case obsLiteServiceUUID:
                // Lite: wir brauchen den TX Notify-Characteristic.
                peripheral.discoverCharacteristics([obsLiteCharTxUUID], for: service)

            case obsClassicServiceUUID:
                // Classic: Distanz/Buttons per Notify + Offset/TrackID per Read.
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
                // Batterie: Level lesen + notify aktivieren.
                peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)

            case deviceInfoServiceUUID:
                // Device Info: Firmware und Hersteller lesen.
                peripheral.discoverCharacteristics(
                    [firmwareRevisionCharUUID, manufacturerNameCharUUID],
                    for: service
                )

            default:
                break
            }
        }
    }

    /// Nach discoverCharacteristics kommt diese Callback.
    /// Hier:
    /// - Characteristics speichern
    /// - Notifications aktivieren oder Werte einmalig lesen
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
                // Lite Events kommen via Notify.
                peripheral.setNotifyValue(true, for: char)

            case obsClassicDistanceCharUUID:
                // Classic Distanzpakete via Notify.
                classicDistanceChar = char
                peripheral.setNotifyValue(true, for: char)

            case obsClassicButtonCharUUID:
                // Classic Buttonpakete via Notify.
                classicButtonChar = char
                peripheral.setNotifyValue(true, for: char)

            case obsClassicOffsetCharUUID:
                // Offset einmalig lesen (Debug/Config).
                classicOffsetChar = char
                peripheral.readValue(for: char)

            case obsClassicTrackIdCharUUID:
                // TrackId einmalig lesen (Debug/Session/Device Info).
                classicTrackIdChar = char
                peripheral.readValue(for: char)

            case batteryLevelCharUUID:
                // Batterie: notify + initial read.
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)

            case firmwareRevisionCharUUID:
                // Firmware: einmal lesen.
                peripheral.readValue(for: char)

            case manufacturerNameCharUUID:
                // Hersteller: einmal lesen.
                peripheral.readValue(for: char)

            default:
                break
            }
        }
    }

    /// Callback wenn Notify an/aus geschaltet wurde.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            ui { self.lastError = "Notify-Fehler: \(error.localizedDescription)" }
        } else {
            print(">> notify state updated for \(characteristic.uuid), isNotifying=\(characteristic.isNotifying)")
        }
    }

    /// Callback für neue Daten:
    /// - entweder durch Notify
    /// - oder als Ergebnis eines readValue(for:)
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        if let error = error {
            ui { self.lastError = "Update-Fehler: \(error.localizedDescription)" }
            return
        }

        guard let data = characteristic.value else { return }

        // UI: Quelle des letzten BLE Updates anzeigen (Debug).
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

        // Dispatch nach Characteristic: die jeweilige Decoder/Handler-Funktion.
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
    // Lite: BLE liefert vollständige Protobuf Events als Data.
    // Wir decodieren, aktualisieren UI und (wenn recording) schreiben wir sie in die BIN-Datei.

    /// Verarbeitet ein Lite BLE-Paket (Protobuf serialisiert).
    /// - decodiert Openbikesensor_Event
    /// - aktualisiert UI/Derived State
    /// - schreibt Event (mit Korrektur + Zeit) in BIN-Datei, wenn Aufnahme läuft
    private func handleLiteUpdate(_ data: Data) {
        print("BLE Lite chunk (\(data.count) Bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        do {
            let event = try Openbikesensor_Event(serializedData: data)
            print("Protobuf decode OK (Lite)")

            ui {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }

            // Schreibt nur, wenn recording + Lite.
            storeIncomingSensorEvent(event)

        } catch {
            let msg = "Protobuf-Decode-Fehler (Lite): \(error.localizedDescription)"
            ui { self.lastError = msg }
            print(msg)
        }
    }

    // -------------------------------------------------
    // MARK: - Classic Pfad (8-Byte-Pakete → CSV)
    // -------------------------------------------------
    // Classic: BLE liefert 8 Byte:
    // [0..3] clockMs (UInt32 LE)
    // [4..5] leftCm (UInt16 LE)  (0xFFFF = invalid)
    // [6..7] rightCm (UInt16 LE) (0xFFFF = invalid)

    /// Decodiert ein Classic 8-Byte Paket in (clockMs, leftCm, rightCm).
    /// Gibt nil zurück, wenn die Länge nicht passt.
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

    /// Verarbeitet Classic Distanzpakete:
    /// - wandelt cm -> Meter (wenn nicht 0xFFFF)
    /// - baut (für UI) ein DistanceMeasurement Event
    /// - bei Classic + Recording: schreibt Messung in CSV (confirmed=false)
    func handleClassicDistanceUpdate(_ data: Data) {
        guard let packet = parseClassicPacket(data) else { return }

        print("BLE Classic distance (\(data.count) Bytes) clock=\(packet.clockMs) left=\(packet.leftCm)cm right=\(packet.rightCm)cm")

        let leftMeters: Double?  = (packet.leftCm  == 0xFFFF) ? nil : Double(packet.leftCm)  / 100.0
        let rightMeters: Double? = (packet.rightCm == 0xFFFF) ? nil : Double(packet.rightCm) / 100.0

        // UI/Preview Event für linke Messung (sourceID=1).
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

            // Hinweis: hier wird nur gespeichert, wenn deviceType == .lite (so ist dein Code).
            // (Falls das unabsichtlich ist: dann wäre es eine mögliche Stelle zum Anpassen.)
            if deviceType == .lite {
                storeIncomingSensorEvent(event)
            }
        }

        // UI/Preview Event für rechte Messung (sourceID=2).
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

            if deviceType == .lite {
                storeIncomingSensorEvent(event)
            }
        }

        // Classic Recording: Messung in CSV schreiben (confirmed=false, da kein Button-Press).
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

    /// Verarbeitet Classic Buttonpakete:
    /// - triggert UI-Preview (Overtake zählen + Median ausgeben)
    /// - bei Classic + Recording: schreibt Messung in CSV (confirmed=true)
    func handleClassicButtonUpdate(_ data: Data) {
        guard let packet = parseClassicPacket(data) else { return }

        print("BLE Classic button (\(data.count) Bytes) clock=\(packet.clockMs) left=\(packet.leftCm)cm right=\(packet.rightCm)cm")

        // Button-Press: erhöhe Überholzähler und nutze Median als "Überholabstand".
        ui { self.handleUserInputPreview() }

        // Classic Recording: Button bedeutet "confirmed" Messung.
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

    /// Classic Offset wird aktuell nur geloggt (Debug).
    private func handleClassicOffsetUpdate(_ data: Data) {
        print("BLE Classic offset bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }

    /// Classic Track-ID wird als UTF-8 String geloggt (Debug).
    private func handleClassicTrackIdUpdate(_ data: Data) {
        if let trackId = String(data: data, encoding: .utf8) {
            print("BLE Classic trackId: \(trackId)")
        } else {
            print("BLE Classic trackId (nicht lesbar): \(data)")
        }
    }

    // -------------------------------------------------
    // MARK: - Batterie / Firmware / Hersteller
    // -------------------------------------------------
    // Handler für Standard-GATT Services.

    /// Batterielevel (0..100) auslesen und in UI-State speichern.
    private func handleBatteryUpdate(_ data: Data) {
        guard let level = data.first else { return }
        ui { self.batteryLevelPercent = Int(level) }
        print("Battery level: \(level)%")
    }

    /// Firmware-Revision als String speichern.
    private func handleFirmwareUpdate(_ data: Data) {
        let fw = String(data: data, encoding: .utf8) ?? ""
        ui { self.firmwareRevision = fw }
        print("Firmware revision: \(fw)")
    }

    /// Herstellername als String speichern.
    private func handleManufacturerUpdate(_ data: Data) {
        let m = String(data: data, encoding: .utf8) ?? ""
        ui { self.manufacturerName = m }
        print("Manufacturer name: \(m)")
    }

    // -------------------------------------------------
    // MARK: - UI / Preview-Logik
    // -------------------------------------------------
    // Aus einem Event werden Textfelder + Roh/Korrekturwerte für UI abgeleitet.

    /// Leitet UI-State aus dem zuletzt empfangenen Event ab.
    /// - aktualisiert Textausgaben
    /// - ruft spezifische Preview-Handler auf (Distance / UserInput)
    fileprivate func updateDerivedState(from event: Openbikesensor_Event) {
        // Grobe Textanzeige je Eventtyp.
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

        // Detail-UI (Roh/Korrektur/Median) je nach Inhalt.
        switch event.content {
        case .distanceMeasurement(let dm)?:
            handleDistancePreview(dm)
        case .userInput(_)?:
            handleUserInputPreview()
        default:
            break
        }
    }

    /// Berechnet Rohdistanz (cm) und korrigierte Distanz (cm) anhand Lenkerbreite/2.
    /// Speichert Werte getrennt für links (sourceID=1) und rechts.
    private func handleDistancePreview(_ dm: Openbikesensor_DistanceMeasurement) {
        let rawMeters = Double(dm.distance)
        let rawCm = Int((rawMeters * 100.0).rounded())

        // Plausibilitätsfilter.
        guard rawMeters > 0.0, rawMeters < 5.0 else { return }

        // Korrektur: Lenkerhalbbreite abziehen.
        let handlebarHalf = Double(handlebarWidthCm) / 2.0
        let correctedCm = max(0, Int((Double(rawCm) - handlebarHalf).rounded()))

        // Median nur aus linkem Sensor speisen (so ist deine Logik).
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

    /// Wird auf Button-Press genutzt:
    /// - erhöht OvertakeCount während Aufnahme
    /// - nimmt aktuellen Median als "Überholabstand"
    private func handleUserInputPreview() {
        if isRecording {
            currentOvertakeCount += 1
        }

        // Wenn noch nicht genug Samples für Median vorhanden sind.
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

    // -------------------------------------------------
    // MARK: - BIN Schreiblogik (nur für Lite)
    // -------------------------------------------------
    // Verantwortlich dafür, Events für die Datei anzureichern (Korrektur + Zeit)
    // und dann COBS-gerahmt zu schreiben.

    /// Nimmt ein eingehendes Sensor-Event, korrigiert ggf. die Distanz
    /// (Lenkerhalbbreite abziehen) und hängt einen Zeitstempel an,
    /// bevor es in die BIN-Datei geschrieben wird.
    private func storeIncomingSensorEvent(_ event: Openbikesensor_Event) {
        guard isRecording, deviceType == .lite else { return }

        var eForFile = event

        // Distanz korrigieren: Rohdistanz - Lenkerhalbbreite.
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

        // Zeitstempel anhängen (Unix).
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

    /// Serialisiert Event als Protobuf, COBS-encodiert und schreibt "frame\0" in die BIN-Datei.
    /// Das Null-Byte (0x00) dient als Frame-Delimiter.
    private func storeEventToBin(_ event: Openbikesensor_Event) {
        guard isRecording, deviceType == .lite else { return }

        do {
            let raw = try event.serializedData()
            let cobs = COBS.encode(raw)

            var frame = Data()
            frame.append(cobs)
            frame.append(0x00) // Frame Ende

            binWriter.write(frame)
        } catch {
            print("storeEventToBin: \(error)")
        }
    }
}

// =====================================================
// MARK: - CLLocationManagerDelegate
// =====================================================
// Reagiert auf Änderungen der Location-Berechtigung.

extension BluetoothManager: CLLocationManagerDelegate {
    /// iOS 14+: Authorization hat eigenen Callback.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateLocationAuthorizationStatus()
    }

    /// Ältere iOS Versionen: alter Callback.
    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        updateLocationAuthorizationStatus()
    }
}

// =====================================================
// MARK: - MovingMedian
// =====================================================
// Hilfsstruktur:
// - sammelt fortlaufend Werte (beschränkt auf maxSamples)
// - liefert Median über die letzten windowSize Werte
// Zweck: stabile "Überholabstand"-Schätzung (Rauschen glätten)

private struct MovingMedian {
    let windowSize: Int
    let maxSamples: Int
    private var values: [Int] = []

    /// Initialisiert die Median-Logik mit:
    /// - windowSize: wie viele der letzten Werte in den Median eingehen
    /// - maxSamples: wie viele Werte maximal gespeichert werden (Speicher/Performance)
    init(windowSize: Int, maxSamples: Int) {
        self.windowSize = max(1, windowSize)
        self.maxSamples = max(windowSize, maxSamples)
    }

    /// Fügt einen neuen Wert hinzu und begrenzt den Puffer auf maxSamples.
    mutating func add(_ value: Int) {
        values.append(value)
        if values.count > maxSamples {
            values.removeFirst(values.count - maxSamples)
        }
    }

    /// true, wenn genügend Werte für einen Median vorhanden sind.
    var hasMedian: Bool {
        values.count >= windowSize
    }

    /// Median der letzten windowSize Werte (oder nil wenn zu wenig Werte vorhanden).
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
