// LossyDecoding.swift

import Foundation

enum AnyJSON: Decodable {
    case null, bool(Bool), number(Double), string(String)
    case array([AnyJSON]), object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([AnyJSON].self) { self = .array(v); return }
        if let v = try? c.decode([String: AnyJSON].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON")
    }
}

/// Decodes an array but skips elements that fail decoding, instead of failing the whole decode.
/// Additionally reports how many elements were skipped.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    let skippedCount: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        var skipped = 0

        while !container.isAtEnd {
            do {
                result.append(try container.decode(Element.self))
            } catch {
                // advance the container by decoding "anything"
                _ = try? container.decode(AnyJSON.self)
                skipped += 1
                print("⚠️ Skipped element due to decode error:", error)
            }
        }

        self.elements = result
        self.skippedCount = skipped
    }
}
