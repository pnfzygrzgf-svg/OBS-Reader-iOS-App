// COBS.swift

import Foundation

/// Einfache COBS-Implementierung,
/// encode() liefert den COBS-Block **ohne** abschließendes 0x00.
/// Das 0x00 wird beim Schreiben der Datei als Frame-Delimiter angehängt.
///
/// COBS = Consistent Overhead Byte Stuffing:
/// - Ziel: Binärdaten so kodieren, dass im Payload **kein einziges 0x00-Byte** vorkommt.
/// - Vorteil: 0x00 kann als eindeutiger Frame-Delimiter benutzt werden.
/// - Idee: Die Daten werden in Blöcke ohne 0x00 aufgeteilt. Jedes Block beginnt mit
///   einem „Code-Byte“, das die Länge des Blocks (inkl. Code-Byte) beschreibt.
///
/// Beispiel grob:
///   [0x11, 0x22, 0x00, 0x33]  ->  [0x03, 0x11, 0x22, 0x02, 0x33]
///   (Das eigentliche Protokoll ist etwas genereller, aber so in etwa.)
enum COBS {
    /// Kodiert einen Datenblock nach COBS.
    ///
    /// - Parameter input: Rohdaten, die 0x00-Bytes enthalten dürfen.
    /// - Returns: COBS-kodierte Daten ohne 0x00. Das abschließende 0x00
    ///            als Frame-Delimiter wird **nicht** angehängt.
    static func encode(_ input: Data) -> Data {
        // Leerer Input -> leere Ausgabe
        if input.isEmpty { return Data() }

        var out = Data()
        var index = input.startIndex

        // Wir iterieren über den Input und erzeugen hintereinander Blöcke,
        // die jeweils mit einem „Code-Byte“ beginnen:
        //
        // Code-Byte = Anzahl der folgenden Nicht-Null-Bytes + 1.
        // Ein Block endet, wenn:
        // - ein 0x00 im Input gefunden wird, oder
        // - die maximale Blocklänge (0xFF) erreicht ist.
        while index < input.endIndex {
            // Platz für Code-Byte reservieren:
            // Wir merken uns die aktuelle Position im Output, fügen
            // ein Dummy-Byte ein (0), und schreiben den echten Wert später.
            let codeIndex = out.count
            out.append(0)
            var code: UInt8 = 1  // Start bei 1, da Code die Blocklänge inkl. Code-Byte angibt

            // Bytes in diesen Block sammeln, bis:
            // - Input zu Ende,
            // - code == 0xFF,
            // - oder ein 0x00 im Input auftaucht.
            while index < input.endIndex && code < 0xFF {
                let b = input[index]
                index = input.index(after: index)

                if b == 0 {
                    // 0x00 beendet den aktuellen Block.
                    // Das 0x00 wird **nicht** in den Output geschrieben,
                    // sondern nur genutzt, um ein neues Code-Byte zu starten.
                    break
                }

                // Nicht-Null-Byte -> in den Output packen,
                // Code um 1 erhöhen (Blocklänge wächst).
                out.append(b)
                code &+= 1
            }

            // Nun kennen wir die tatsächliche Blocklänge -> Code-Byte setzen.
            out[codeIndex] = code
        }

        // WICHTIG:
        // - Hier KEIN 0x00 anhängen, da das Protokoll (z. B. OBSFileWriter)
        //   dieses Delimiter-Byte selbst ergänzt, um Frames zu trennen.
        return out
    }
}
