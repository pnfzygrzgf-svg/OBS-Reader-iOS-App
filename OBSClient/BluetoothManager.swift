import Foundation
import CoreBluetooth
import SwiftProtobuf
import Combine
import CoreLocation

// UUIDs müssen mit der Firmware übereinstimmen
// Service-UUID des OpenBikeSensor
private let obsServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
// Charakteristik-UUID für TX (Daten vom OBS -> iPhone)
private let obsCharTxUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

/// Zentrale Bluetooth-Verwaltung + Standort + Aufnahmelogik
/// - kümmert sich ums Scannen, Verbinden, Lesen der BLE-Daten
/// - schreibt Events in eine BIN-Datei im OBS-Format
/// - berechnet Vorschauwerte für die UI
final class BluetoothManager: NSObject, ObservableObject {

    // MARK: - Published State
    // Diese Properties sind mit SwiftUI/Combine verknüpft und aktualisieren das UI automatisch.

    /// Ist Bluetooth auf Systemebene eingeschaltet?
    @Published var isPoweredOn: Bool = false
    /// Ist aktuell ein OpenBikeSensor verbunden?
    @Published var isConnected: Bool = false
    /// Läuft gerade eine Aufnahmesession (BIN-Datei)?
    @Published var isRecording: Bool = false

    /// Hat die App Bluetooth-Berechtigung (iOS-Authorization)?
    @Published var hasBluetoothPermission: Bool = true

    /// Sind Standortdienste (GPS) auf Systemebene aktiviert?
    @Published var isLocationEnabled: Bool = false

    /// Hat die App Standort-Berechtigung "Immer"?
    @Published var hasLocationAlwaysPermission: Bool = false

    /// Zuletzt empfangenes OBS-Event (vom Sensor oder GPS)
    @Published var lastEvent: Openbikesensor_Event?
    /// Letzte Fehlermeldung für das UI
    @Published var lastError: String?

    /// Einfacher Text mit letzter Distanz (für Debug/Anzeige)
    @Published var lastDistanceText: String = "Noch keine Messung. Starte eine Aufnahme, um Werte zu sehen."

    /// Letzte Text-/UserInput-Nachricht des Sensors
    @Published var lastMessageText: String = ""

    /// Vorschau-Texte für linke/rechte Seite und Überholabstand
    @Published var leftDistanceText: String = "Links: Noch keine Messung."
    @Published var rightDistanceText: String = "Rechts: Noch keine Messung."
    @Published var overtakeDistanceText: String = "Überholabstand: Noch keine Messung."

    /// Letzter Median am Zeitpunkt eines Button-Drucks (cm)
    @Published var lastMedianAtPressCm: Int?

    /// Roh- und korrigierte Werte in cm für die beiden Sensoren (für ContentView-Anzeige)
    @Published var leftRawCm: Int?
    @Published var leftCorrectedCm: Int?

    @Published var rightRawCm: Int?
    @Published var rightCorrectedCm: Int?

    /// Letzter berechneter Überholabstand in cm (für UI-Anzeige)
    @Published var overtakeDistanceCm: Int?

    /// Lenkerbreite in cm (einstellbar im UI, mit Min/Max-Begrenzung)
    @Published var handlebarWidthCm: Int = 60 {
        didSet {
            // Eingabe begrenzen, damit keine unsinnigen Werte gespeichert werden
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

    /// CoreBluetooth-Zentrale zum Scannen/Verbinden
    private var central: CBCentralManager!
    /// Das verbundene OBS-Peripheral (wenn vorhanden)
    private var peripheral: CBPeripheral?
    /// Charakteristik, auf der die Daten-Notifications kommen
    private var notifyCharacteristic: CBCharacteristic?

    /// Median über korrigierte Abstände (nur Sensor sourceID == 1, linker Sensor)
    /// - windowSize: wie viele letzte Werte zur Median-Berechnung
    /// - maxSamples: maximal gespeicherte Historie (Speicherlimit)
    private var movingMedian = MovingMedian(windowSize: 3,
                                            maxSamples: 122)

    /// Location Manager nur zur Abfrage der Berechtigung und Statusänderungen
    private let locationManager = CLLocationManager()

    /// Writer für die BIN-Datei im OBS-Binärformat
    private let binWriter = OBSFileWriter()

    /// Letzte GPS-Position während der Aufnahme (für Distanz-Berechnung Segment für Segment)
    private var lastLocation: CLLocation?

    // MARK: - Init

    override init() {
        super.init()

        // Gespeicherte Lenkerbreite laden (falls vorhanden)
        let stored = UserDefaults.standard.integer(forKey: "handlebarWidthCm")
        if stored != 0 {
            handlebarWidthCm = stored
        }

        // Bluetooth-Central initialisieren
        // CBCentralManagerOptionShowPowerAlertKey: false unterdrückt das System-Pop-up,
        // falls Bluetooth ausgeschaltet ist.
        central = CBCentralManager(
            delegate: self,
            queue: nil, // main queue
            options: [
                CBCentralManagerOptionShowPowerAlertKey: false
            ]
        )

        // Location-Berechtigung beobachten
        locationManager.delegate = self
        updateLocationAuthorizationStatus()
    }

    // MARK: - Recording API
    // Öffentliche Methoden, um eine Mess-Session zu starten/beenden.

    /// Startet eine neue Aufnahmesession
    func startRecording() {
        // Neue Datei / Session im Writer beginnen
        binWriter.startSession()
        DispatchQueue.main.async {
            // Zähler und Distanz zurücksetzen
            self.currentOvertakeCount = 0
            self.currentDistanceMeters = 0
            self.lastLocation = nil
            self.isRecording = true
        }
    }

    /// Beendet die aktuelle Aufnahmesession und hängt Statistik an die Datei an
    func stopRecording() {
        // Session beenden und Datei schließen
        binWriter.finishSession()

        // Zähler & Distanz an die entstandene Datei "dranhängen"
        if let fileURL = binWriter.fileURL {
            let hasCount = currentOvertakeCount > 0
            let hasDistance = currentDistanceMeters > 0.0

            // Nur schreiben, wenn es auch wirklich Werte gibt
            if hasCount || hasDistance {
                OvertakeStatsStore.store(
                    count: hasCount ? currentOvertakeCount : nil,
                    distanceMeters: hasDistance ? currentDistanceMeters : nil,
                    for: fileURL
                )
            }
        }

        // Aufnahmeflag im UI zurücksetzen
        DispatchQueue.main.async {
            self.isRecording = false
            // currentOvertakeCount & currentDistanceMeters bleiben stehen,
            // damit das UI sie nach dem Stoppen anzeigen kann
        }
    }

    /// Wird vom LocationManager oder App-Code aufgerufen, um GPS-Geolocation-Events zu schreiben
    /// und die gefahrene Distanz live zu summieren.
    func handleLocationUpdate(_ location: CLLocation) {
        // Nur während einer laufenden Aufnahme interessiert uns GPS
        guard isRecording else { return }

        // 1) Distanz live aufsummieren
        if let prev = lastLocation {
            let segment = location.distance(from: prev) // Distanz in Metern
            // einfache Plausibilitätsfilter gegen Ausreißer (z.B. Sprünge im GPS)
            if segment > 0, segment < 2000 {
                currentDistanceMeters += segment
            }
        }
        // Aktuelle Position merken für das nächste Segment
        lastLocation = location

        // 2) BIN: Geolocation-Event erstellen und schreiben
        var geo = Openbikesensor_Geolocation()
        geo.latitude = location.coordinate.latitude
        geo.longitude = location.coordinate.longitude
        geo.altitude = location.altitude
        // Negative Geschwindigkeiten vermeiden (z.B. bei ungültigen Werten)
        geo.groundSpeed = Float(max(location.speed, 0))
        geo.hdop = Float(location.horizontalAccuracy)

        // Zeitstempel im OBS-Time-Format aufbauen (Unix-Zeit)
        var t = Openbikesensor_Time()
        let ts = location.timestamp.timeIntervalSince1970
        let sec = Int64(ts)
        let nanos = Int32((ts - Double(sec)) * 1_000_000_000)
        t.sourceID = 3
        t.seconds = sec
        t.nanoseconds = nanos
        t.reference = .unix

        // Event zusammenbauen
        var event = Openbikesensor_Event()
        event.geolocation = geo
        event.time = [t]

        // Event in BIN-Datei speichern
        storeEventToBin(event)
    }

    // MARK: - Location-Berechtigung

    /// Liest den aktuellen Standort-Berechtigungs- und Dienstestatus aus
    /// und aktualisiert die Published-Properties für das UI.
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
// Hier wird auf Änderungen des Bluetooth-Zustands & Verbindungsstatus reagiert.

extension BluetoothManager: CBCentralManagerDelegate {

    /// Wird aufgerufen, wenn sich der Bluetooth-Status ändert (ein/aus, Berechtigung etc.)
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Berechtigung bestimmen
        let hasPermission: Bool
        if #available(iOS 13.0, *) {
            let auth = CBCentralManager.authorization
            hasPermission = (auth == .allowedAlways)
        } else {
            // Vor iOS 13 gab es dieses API noch nicht, daher: assume true
            hasPermission = true
        }

        // UI-Status aktualisieren
        DispatchQueue.main.async {
            self.hasBluetoothPermission = hasPermission
            self.isPoweredOn = (central.state == .poweredOn)
            if central.state != .poweredOn {
                self.isConnected = false
            }
        }

        // Ohne Power oder ohne Berechtigung: nichts scannen
        guard central.state == .poweredOn, hasPermission else { return }

        // Nach OpenBikeSensor-Peripherals scannen, die den passenden Service anbieten
        central.scanForPeripherals(
            withServices: [obsServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Wird aufgerufen, wenn ein passendes Peripheral gefunden wird
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        // Gefundenes OBS-Peripheral merken
        self.peripheral = peripheral
        self.peripheral?.delegate = self

        // Scan stoppen, damit wir uns verbinden können
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    /// Erfolgreich mit Peripheral verbunden
    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.lastError = nil
        }
        // Nach dem OBS-Service auf dem Peripheral suchen
        peripheral.discoverServices([obsServiceUUID])
    }

    /// Verbindungsaufbau ist fehlgeschlagen
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = error?.localizedDescription ?? "Verbindung fehlgeschlagen"
        }

        // Erneut scannen, um es wieder zu versuchen
        central.scanForPeripherals(
            withServices: [obsServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Peripheral wurde getrennt (gewollt oder ungewollt)
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            if let error = error {
                self.lastError = error.localizedDescription
            }
        }

        // Automatisch neu scannen, um ggf. wieder zu verbinden
        central.scanForPeripherals(
            withServices: [obsServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

// MARK: - CBPeripheralDelegate
// Hier werden Services, Charakteristiken und Daten vom verbundenen OBS behandelt.

extension BluetoothManager: CBPeripheralDelegate {
    /// Services wurden entdeckt
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.lastError = "Service-Fehler: \(error.localizedDescription)"
            }
            return
        }

        guard let services = peripheral.services else { return }
        // Nach dem OBS-Service filtern und passende Charakteristiken suchen
        for service in services where service.uuid == obsServiceUUID {
            peripheral.discoverCharacteristics([obsCharTxUUID], for: service)
        }
    }

    /// Charakteristiken innerhalb eines Services wurden entdeckt
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
            // Charakteristik merken und Notifications aktivieren
            self.notifyCharacteristic = char
            peripheral.setNotifyValue(true, for: char)
        }
    }

    /// Notification-Status einer Charakteristik hat sich geändert
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.lastError = "Notify-Fehler: \(error.localizedDescription)"
            }
        }
    }

    /// Neue Daten vom OBS über die TX-Charakteristik
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        if let error = error {
            DispatchQueue.main.async {
                self.lastError = "Update-Fehler: \(error.localizedDescription)"
            }
            return
        }

        // Nur unsere erwartete Charakteristik auswerten
        guard characteristic.uuid == obsCharTxUUID,
              let data = characteristic.value else { return }

        // Debug-Ausgabe des rohen BLE-Frames im Hex-Format
        print("BLE chunk (\(data.count) Bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        do {
            // Protobuf-Decode in ein Openbikesensor_Event
            let event = try Openbikesensor_Event(serializedData: data)
            print("Protobuf decode OK")

            // UI / Vorschau aktualisieren
            DispatchQueue.main.async {
                self.lastEvent = event
                self.lastError = nil
                self.updateDerivedState(from: event)
            }

            // Event in BIN-Datei aufnehmen (ggf. mit zusätzlichem Zeitstempel)
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

    /// Erzeugt abgeleitete UI-Zustände (Texte, Vorschauwerte) aus einem OBS-Event.
    fileprivate func updateDerivedState(from event: Openbikesensor_Event) {
        // Anzeige / Preview je nach Event-Typ
        switch event.content {
        case .distanceMeasurement(let dm)?:
            let d = Double(dm.distance)

            // Nur sinnvolle Messwerte anzeigen (zwischen 0 und 5 m)
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
            // Freitextnachricht vom Sensor
            lastMessageText = msg.text

        case .userInput(let ui)?:
            // Button-/User-Eingabe vom Sensor
            lastMessageText = "UserInput: \(ui.type)"

        case .geolocation?, .metadata?, .batteryStatus?:
            // Diese Typen werden für die Preview hier nicht explizit verwendet
            break

        case nil:
            break
        }

        // Erweiterte Vorschau-Logik (Abstände, Überholabstand)
        switch event.content {
        case .distanceMeasurement(let dm)?:
            handleDistancePreview(dm)

        case .userInput(_)?:
            handleUserInputPreview()

        default:
            break
        }
    }

    /// Aktualisiert die linke/rechte Distanz-Vorschau und speichert Korrekturwerte.
    private func handleDistancePreview(_ dm: Openbikesensor_DistanceMeasurement) {
        let rawMeters = Double(dm.distance)
        let rawCm = Int((rawMeters * 100.0).rounded())

        // Nur Werte im Bereich 0–5 m verwenden
        guard rawMeters > 0.0, rawMeters < 5.0 else {
            // 99m/Timeout nicht in der Preview verwenden
            return
        }

        // Lenkerbreite abziehen, um den Abstand zum überholenden Fahrzeug zu erhalten
        let handlebarHalf = Double(handlebarWidthCm) / 2.0
        let correctedCm = max(0, Int((Double(rawCm) - handlebarHalf).rounded()))

        // Für den Median nur die Messungen des linken Sensors (ID 1) verwenden
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

    /// Wird bei einem UserInput-Event aufgerufen (z.B. Buttondruck am OBS).
    /// Nutzt den aktuellen Median, um den Überholabstand festzuhalten.
    private func handleUserInputPreview() {
        // Jeder UserInput während der Aufnahme = ein Überholvorgang
        if isRecording {
            currentOvertakeCount += 1
        }

        // Wenn noch kein stabiler Median vorhanden ist, kann kein sinnvoller Überholabstand berechnet werden
        guard let median = movingMedian.currentMedian else {
            overtakeDistanceText = "Überholabstand: Noch keine Messung."
            lastMedianAtPressCm = nil
            overtakeDistanceCm = nil
            return
        }

        // Median am Zeitpunkt des Tastendrucks übernehmen
        lastMedianAtPressCm = median
        overtakeDistanceCm = median
        overtakeDistanceText = "Überholabstand: \(median) cm"
    }

    // MARK: - BIN Schreiblogik

    /// Nimmt ein vom Sensor empfangenes Event und versieht es mit einem zusätzlichen Zeitstempel,
    /// bevor es in die BIN-Datei geschrieben wird.
    private func storeIncomingSensorEvent(_ event: Openbikesensor_Event) {
        // Nur während einer laufenden Aufnahme speichern
        guard isRecording else { return }

        var e = event

        // Aktuelle Zeit als OBS-Time an das Event anhängen
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

    /// Serialisiert ein Event, verpackt es per COBS und schreibt es in die BIN-Datei.
    private func storeEventToBin(_ event: Openbikesensor_Event) {
        // Nur während einer laufenden Aufnahme speichern
        guard isRecording else { return }

        do {
            // Protobuf serialisieren
            let raw = try event.serializedData()
            // Frame mit COBS kodieren (für robuste, 0-terminierte Frames)
            let cobs = COBS.encode(raw)
            var frame = Data()
            frame.append(cobs)
            frame.append(0x00) // Frame-Delimiter (0x00 trennt die Frames)

            // Binärdaten in Datei schreiben
            binWriter.write(frame)
        } catch {
            print("storeEventToBin: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate
// Reagiert auf Änderungen der Standortberechtigung.

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

/// Einfacher gleitender Median über die letzten N Werte.
/// Wird verwendet, um Überholabstände zu glätten und Ausreißer zu reduzieren.
private struct MovingMedian {
    /// Anzahl Werte in einem Fenster (z.B. 3)
    let windowSize: Int
    /// Maximale Anzahl an Werten, die insgesamt gespeichert werden
    let maxSamples: Int

    /// Bisher aufgezeichnete Werte (FIFO-Logik in `add`)
    private var values: [Int] = []

    init(windowSize: Int, maxSamples: Int) {
        // windowSize und maxSamples absichern
        self.windowSize = max(1, windowSize)
        self.maxSamples = max(windowSize, maxSamples)
    }

    /// Fügt einen neuen Wert hinzu und schneidet ggf. die Historie ab.
    mutating func add(_ value: Int) {
        var v = values
        v.append(value)
        // Wenn zu viele Werte gespeichert sind, die ältesten abschneiden
        if v.count > maxSamples {
            v.removeFirst(v.count - maxSamples)
        }
        values = v
    }

    /// Ist genügend Historie vorhanden, um einen Median zu berechnen?
    var hasMedian: Bool {
        values.count >= windowSize
    }

    /// Aktueller Median über die letzten `windowSize` Werte (falls vorhanden).
    var currentMedian: Int? {
        guard hasMedian else { return nil }
        // Nur die letzten `windowSize` Werte verwenden
        let slice = values.suffix(windowSize)
        let sorted = slice.sorted()
        let count = sorted.count
        let mid = count / 2

        // Bei ungerader Anzahl: mittleres Element
        if count % 2 == 1 {
            return sorted[mid]
        } else {
            // Bei gerader Anzahl: Mittelwert der beiden mittleren Elemente
            let m = Double(sorted[mid - 1] + sorted[mid]) / 2.0
            return Int(m.rounded())
        }
    }
}
