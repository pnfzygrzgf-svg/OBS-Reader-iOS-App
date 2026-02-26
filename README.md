[Deutsch](#obs-recorder-für-ios) | [English](#obs-recorder-for-ios)

---

# OBS Recorder für iOS

OBS Recorder für iOS ist eine App zum Aufzeichnen von Fahrten mit einem **[OpenBikeSensor Classic](https://www.openbikesensor.org/docs/classic/)** oder einem **[OpenBikeSensor Lite](https://www.openbikesensor.org/docs/lite/)** und zum Hochladen dieser in ein OpenBikeSensor-Portal. Die aufgezeichneten Fahrten können ebenfalls direkt auf dem Gerät auf einer Karte dargestellt werden.

Code, der in dieser App verwendet wird, stammt von https://github.com/openbikesensor.  
Als Basis wurde ebenfalls Code aus der SimRa-App verwendet: https://github.com/simra-project/simra-android/tree/master  
Das verwendete Logo wurde erstellt durch Lukas Betzler, https://github.com/pnfzygrzgf-svg/OpenBikeSensor-Logo

Die App ist mittels *Vibecoding* erstellt worden. **Don't trust, verify!**

Der OBS-Lite kommuniziert über BLE mit dem iPhone. Dazu muss die angepasste Firmware auf dem ESP installiert werden: https://github.com/pnfzygrzgf-svg/firmware-lite

## Download und Installation der App

Diese Anleitung erklärt, wie du den Code lokal auscheckst und die App auf einem iPhone installierst (über Xcode).

### Voraussetzungen

**Hardware / System**
- **Mac** mit **macOS** (Xcode läuft nur auf macOS)
- **iPhone** + USB-Kabel (oder später WLAN-Debugging)

**Software**
- **Xcode** (Mac App Store)
- **Git** (optional, aber empfohlen)

**Apple Account**
- Eine **Apple ID** reicht, um die App auf **deinem eigenen Gerät** zu installieren (Personal Team).

**iPhone: Entwicklermodus**  
Bei iOS 16+ muss **Developer Mode** aktiv sein:  
*Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → Aktivieren* (danach Neustart)

---

### 1) Repository lokal holen

```bash
git clone https://github.com/pnfzygrzgf-svg/OBS-Reader-iOS-App.git
cd OBS-Reader-iOS-App
```

### 2) Projekt in Xcode öffnen

1. **Xcode** öffnen
2. **File → Open…**
3. Die Datei **`OBSClient.xcodeproj`** im Repo auswählen und öffnen

---

### 3) Signierung konfigurieren (wichtig für Installation auf iPhone)

1. In Xcode links im Navigator ganz oben auf das **Projekt** klicken
2. Unter **Targets** das **App-Target** auswählen
3. Reiter **Signing & Capabilities**
4. Setze:
   - **Automatically manage signing**
   - **Team:** deine Apple ID / **Personal Team**

Wenn Xcode deine Apple ID nicht kennt:
- **Xcode → Settings… → Accounts → +** → Apple ID hinzufügen

**Bundle Identifier anpassen (falls nötig)**  
Wenn du einen Fehler wie „No profiles for … were found" bekommst:
1. Ändere den **Bundle Identifier** auf einen eindeutig eigenen Wert, z. B.:
   - `ch.deinname.obsreader`
   - `com.deinname.obsclient`
2. Danach wieder **Team** auswählen und **Automatically manage signing** aktivieren

---

### 4) iPhone verbinden & App starten (Run)

1. iPhone per USB verbinden
2. Auf dem iPhone **„Diesem Computer vertrauen?" → Vertrauen**
3. In Xcode oben in der Toolbar als Run-Ziel dein **iPhone** auswählen
4. Auf **▶ Run** klicken

Xcode baut jetzt die App und installiert sie auf deinem iPhone.

---

### 5) Auf dem iPhone dem Entwickler vertrauen (falls nötig)

Wenn beim Start **„Untrusted Developer / Nicht vertrauenswürdiger Entwickler"** erscheint:
1. **Einstellungen → Allgemein → VPN & Geräteverwaltung**
2. Entwicklerprofil auswählen
3. **Vertrauen**

## OpenBikeSensor

Ein offenes System für die Überholabstandsmessung am Fahrrad.  
https://www.openbikesensor.org/  
https://github.com/openbikesensor

---

# OBS Recorder for iOS

OBS Recorder for iOS is an app for recording rides with an **[OpenBikeSensor Classic](https://www.openbikesensor.org/docs/classic/)** or an **[OpenBikeSensor Lite](https://www.openbikesensor.org/docs/lite/)** and uploading them to an OpenBikeSensor portal. Recorded rides can also be displayed directly on the device on a map.

Code used in this app originates from https://github.com/openbikesensor.  
The app is also based on code from the SimRa app: https://github.com/simra-project/simra-android/tree/master  
The logo was created by Lukas Betzler, https://github.com/pnfzygrzgf-svg/OpenBikeSensor-Logo

This app was created using *vibecoding*. **Don't trust, verify!**

The OBS Lite communicates with the iPhone via BLE. The custom firmware must be installed on the ESP: https://github.com/pnfzygrzgf-svg/firmware-lite

## Download and Installation

This guide explains how to check out the code locally and install the app on an iPhone (via Xcode).

### Prerequisites

**Hardware / System**
- **Mac** running **macOS** (Xcode runs on macOS only)
- **iPhone** + USB cable (or Wi-Fi debugging later)

**Software**
- **Xcode** (Mac App Store)
- **Git** (optional, but recommended)

**Apple Account**
- A free **Apple ID** is sufficient to install the app on **your own device** (Personal Team).

**iPhone: Developer Mode**  
On iOS 16+, **Developer Mode** must be enabled:  
*Settings → Privacy & Security → Developer Mode → Enable* (restart required)

---

### 1) Clone the repository

```bash
git clone https://github.com/pnfzygrzgf-svg/OBS-Reader-iOS-App.git
cd OBS-Reader-iOS-App
```

### 2) Open the project in Xcode

1. Open **Xcode**
2. **File → Open…**
3. Select the file **`OBSClient.xcodeproj`** in the repo and open it

---

### 3) Configure signing (required for installation on iPhone)

1. In Xcode, click the **project** at the top of the left navigator
2. Under **Targets**, select the **app target**
3. Go to the **Signing & Capabilities** tab
4. Set:
   - **Automatically manage signing**
   - **Team:** your Apple ID / **Personal Team**

If Xcode doesn't know your Apple ID:
- **Xcode → Settings… → Accounts → +** → Add Apple ID

**Adjust Bundle Identifier (if needed)**  
If you get an error like "No profiles for … were found":
1. Change the **Bundle Identifier** to a unique value, e.g.:
   - `ch.yourname.obsreader`
   - `com.yourname.obsclient`
2. Then re-select your **Team** and enable **Automatically manage signing**

---

### 4) Connect iPhone & run the app

1. Connect your iPhone via USB
2. On the iPhone: **"Trust This Computer?" → Trust**
3. In Xcode, select your **iPhone** as the run target in the toolbar
4. Click **▶ Run**

Xcode will build the app and install it on your iPhone.

---

### 5) Trust the developer on iPhone (if needed)

If you see **"Untrusted Developer"** when launching the app:
1. **Settings → General → VPN & Device Management**
2. Select the developer profile
3. **Trust**

## OpenBikeSensor

An open system for measuring overtaking distances while cycling.  
https://www.openbikesensor.org/  
https://github.com/openbikesensor
