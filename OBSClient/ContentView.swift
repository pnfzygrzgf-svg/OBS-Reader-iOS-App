import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                // MARK: - Logo im Inhalt zentriert
                Image("OBSLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .frame(maxWidth: .infinity, alignment: .center)

                // MARK: - Verbindungsstatus
                HStack(spacing: 8) {
                    Circle()
                        .fill(bt.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bt.isConnected ? "Verbunden mit OBS" : "Nicht verbunden")
                            .font(.headline)

                        Text(bt.isPoweredOn ? "Bluetooth an" : "Bluetooth AUS")
                            .font(.subheadline)
                            .foregroundStyle(bt.isPoweredOn ? .secondary : Color.red)
                    }

                    Spacer()
                }

                // MARK: - Sensor LINKS
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensor links")
                        .font(.headline)

                    Text(rawText(for: bt.leftRawCm))
                        .font(.system(size: 22, weight: .regular, design: .monospaced))

                    Text(correctedText(for: bt.leftCorrectedCm))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // MARK: - Sensor RECHTS
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensor rechts")
                        .font(.headline)

                    Text(rawText(for: bt.rightRawCm))
                        .font(.system(size: 22, weight: .regular, design: .monospaced))

                    Text(correctedText(for: bt.rightCorrectedCm))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // MARK: - Überholabstand
                VStack(alignment: .leading, spacing: 8) {
                    Text("Überholabstand")
                        .font(.headline)

                    Text(bt.overtakeDistanceText)
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // MARK: - Lenkerbreite
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lenkerbreite")
                        .font(.headline)

                    Stepper(
                        "\(bt.handlebarWidthCm) cm",
                        value: $bt.handlebarWidthCm,
                        in: 30...120,
                        step: 1
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // MARK: - Aufnahme-Button
                Button(action: {
                    if bt.isRecording {
                        bt.stopRecording()
                    } else {
                        bt.startRecording()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: bt.isRecording ? "stop.circle.fill" : "record.circle.fill")
                        Text(bt.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
                    }
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        bt.isRecording
                        ? Color.red.opacity(0.2)
                        : Color.green.opacity(0.2)
                    )
                    .clipShape(Capsule())
                }

            }
            .padding()
            .navigationTitle("OBS Lite Recorder")    // kurzer Titel, der nicht abgeschnitten wird
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        DataExportView()
                    } label: {
                        Image(systemName: "folder")
                    }

                    NavigationLink {
                        InfoView()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
    }

    // MARK: - Hilfsfunktionen

    private func rawText(for value: Int?) -> String {
        if let v = value {
            return "Roh: \(v) cm"
        } else {
            return "Roh: –"
        }
    }

    private func correctedText(for value: Int?) -> String {
        if let v = value {
            return "Korrigiert: \(v) cm"
        } else {
            return "Korrigiert: –"
        }
    }
}
