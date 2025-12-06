import Foundation

/// Einfache COBS-Implementierung (wie auf Android),
/// encode() liefert den COBS-Block OHNE abschließendes 0x00.
/// Das 0x00 wird beim Schreiben der Datei als Frame-Delimiter angehängt.
enum COBS {
    static func encode(_ input: Data) -> Data {
        if input.isEmpty { return Data() }

        var out = Data()
        var index = input.startIndex

        while index < input.endIndex {
            // Platz für Code-Byte
            let codeIndex = out.count
            out.append(0)
            var code: UInt8 = 1

            while index < input.endIndex && code < 0xFF {
                let b = input[index]
                index = input.index(after: index)

                if b == 0 {
                    // 0x00 beendet Block, nächstes Code-Byte folgt
                    break
                }
                out.append(b)
                code &+= 1
            }

            out[codeIndex] = code
        }

        return out
    }
}
