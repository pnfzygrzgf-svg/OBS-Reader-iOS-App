// SPDX-License-Identifier: GPL-3.0-or-later

//
//  LiteBinRecorder.swift
//

import Foundation
import SwiftProtobuf

/// Recorder für OBS Lite (Protobuf -> COBS framing -> .bin via OBSFileWriter)
///
/// Zuständigkeit:
/// - Session (start/finish)
/// - Event vorbereiten (Lenker-Korrektur, Timestamp)
/// - Protobuf serialisieren
/// - COBS encode + 0x00 Delimiter anhängen
/// - Bytes an OBSFileWriter schreiben
final class LiteBinRecorder {

    private let writer: OBSFileWriter

    /// URL der aktuellen BIN-Datei (falls Session läuft).
    var fileURL: URL? { writer.fileURL }

    init(writer: OBSFileWriter = OBSFileWriter()) {
        self.writer = writer
    }

    func startSession() {
        writer.startSession()
    }

    func finishSession() {
        writer.finishSession()
    }

    /// Schreibt ein Event in die BIN-Datei (nur sinnvoll während einer Session).
    ///
    /// - Parameter handlebarWidthCm: volle Lenkerbreite (cm). Es wird `width/2` abgezogen.
    func record(event: Openbikesensor_Event, handlebarWidthCm: Int) {
        var eForFile = event

        // DistanceMeasurement: korrigieren (gemessen - halbe Lenkerbreite)
        if case .distanceMeasurement(var dm) = eForFile.content {
            let rawMeters = Double(dm.distance)
            if rawMeters > 0 {
                let halfHandlebarCm = Double(handlebarWidthCm) / 2.0
                let correctedMeters = max(0.0, rawMeters - (halfHandlebarCm / 100.0))
                dm.distance = Float(correctedMeters)
                eForFile.distanceMeasurement = dm
            }
        }

        // Timestamp (Unix) anhängen
        var t = Openbikesensor_Time()
        let now = Date().timeIntervalSince1970
        let sec = Int64(now)
        let nanos = Int32((now - Double(sec)) * 1_000_000_000)

        t.sourceID = 3
        t.seconds = sec
        t.nanoseconds = nanos
        t.reference = .unix

        eForFile.time.append(t)

        do {
            let raw = try eForFile.serializedData()
            let cobs = COBS.encode(raw)

            var frame = Data()
            frame.append(cobs)
            frame.append(0x00) // Frame-Delimiter

            writer.write(frame)
        } catch {
            print("LiteBinRecorder.record error: \(error)")
        }
    }
}
