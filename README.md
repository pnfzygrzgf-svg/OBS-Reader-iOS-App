# OBS Recorder für iOS

OBS  Recorder für iOS ist eine App zum Aufzeichnen von Fahrten mit einem **[OpenBikeSensor Classic](https://www.openbikesensor.org/docs/classic/)** oder einem **[OpenBikeSensor Lite](https://www.openbikesensor.org/docs/lite/)** und zum Hochladen dieser in ein
OpenBikeSensor-Portal. Die aufgezeichneten Fahrten können ebenfalls direkt auf dem Gerät auf einer Karte dargestellt werden.

Code, der in dieser App verwendet wird, stammt von https://github.com/openbikesensor.

Als Basis wurde ebenfalls Code aus der SimRa-App verwendet: https://github.com/simra-project/simra-android/tree/master

Das verwendete Logo wurde erstellt durch Lukas
Betzler, https://github.com/pnfzygrzgf-svg/OpenBikeSensor-Logo

Die App ist mittels *Vibecoding* erstellt worden. **Don't trust verify!**

Der OBS-Lite kommuniziert über BLE mit dem iPhone. Dazu muss die angepasste Firmware auf dem ESP installiert werden: https://github.com/pnfzygrzgf-svg/firmware-lite


# Download und Installation der App

Diese Anleitung erklärt, wie du den Code lokal auscheckst und die App auf einem iPhone installierst (über Xcode).

## Voraussetzungen

### Hardware / System
- **Mac** mit **macOS** (Xcode läuft nur auf macOS)
- **iPhone** + USB-Kabel (oder später WLAN-Debugging)

### Software
- **Xcode** (Mac App Store)
- **Git** (optional, aber empfohlen)

### Apple Account
- Eine **Apple ID** reicht, um die App auf **deinem eigenen Gerät** zu installieren (Personal Team).

### iPhone: Entwicklermodus
Bei iOS 16+ muss **Developer Mode** aktiv sein:
- *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → Aktivieren* (danach Neustart)

---

## 1) Repository lokal holen

Mit Gi

```bash
git clone https://github.com/pnfzygrzgf-svg/OBS-Reader-iOS-App.git
cd OBS-Reader-iOS-App
```

## 2) Projekt in Xcode öffnen

1. **Xcode** öffnen
2. **File → Open…**
3. Die Datei **`OBSClient.xcodeproj`** im Repo auswählen und öffnen

---

## 3) Signierung konfigurieren (wichtig für Installation auf iPhone)

1. In Xcode links im Navigator ganz oben auf das **Projekt** klicken
2. Unter **Targets** das **App-Target** auswählen
3. Reiter **Signing & Capabilities**
4. Setze:
   - **Automatically manage signing**
   - **Team:** deine Apple ID / **Personal Team**

Wenn Xcode deine Apple ID nicht kennt:
- **Xcode → Settings… → Accounts → +** → Apple ID hinzufügen

### Bundle Identifier anpassen (falls nötig)

Wenn du einen Fehler wie „No profiles for … were found“ bekommst:

1. Ändere den **Bundle Identifier** auf einen eindeutig eigenen Wert, z. B.:
   - `ch.deinname.obsreader`
   - `com.deinname.obsclient`
2. Danach wieder:
   - **Team** auswählen
   - **Automatically manage signing** aktivieren

---

## 4) iPhone verbinden & App starten (Run)

1. iPhone per USB verbinden
2. Auf dem iPhone **„Diesem Computer vertrauen?“ → Vertrauen**
3. In Xcode oben in der Toolbar als Run-Ziel dein **iPhone** auswählen
4. Auf **▶ Run** klicken

Xcode baut jetzt die App und installiert sie auf deinem iPhone.

---

## 5) Auf dem iPhone dem Entwickler vertrauen (falls nötig)

Wenn beim Start **„Untrusted Developer / Nicht vertrauenswürdiger Entwickler“** erscheint:

1. **Einstellungen → Allgemein → VPN & Geräteverwaltung**
2. Entwicklerprofil auswählen
3. **Vertrauen**



# OpenBikeSensor

ein offenes System für die Überholabstands­messung am Fahrrad.

https://www.openbikesensor.org/

https://github.com/openbikesensor
