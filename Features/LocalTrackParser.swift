// SPDX-License-Identifier: GPL-3.0-or-later

// LocalTrackParser.swift

import Foundation
import CoreLocation
import SwiftProtobuf

/// Geparste Daten einer lokalen Fahrt (CSV oder BIN-Datei)
struct LocalTrackData {
    /// Route als Koordinaten
    let route: [CLLocationCoordinate2D]

    /// Überholvorgänge (bestätigte Events)
    let events: [OvertakeEvent]

    /// Gesamtdistanz in Metern (berechnet aus GPS-Punkten)
    let distanceMeters: Double

    /// Anzahl Datenpunkte
    let measurementCount: Int
}

/// Parser für OBS-Dateien (CSV und BIN/Protobuf)
struct LocalTrackParser {

    /// Parst eine Datei und extrahiert Route + Events
    /// Erkennt automatisch das Format anhand der Dateiendung
    static func parse(fileURL: URL) throws -> LocalTrackData {
        let ext = fileURL.pathExtension.lowercased()

        if ext == "bin" {
            return try parseBin(fileURL: fileURL)
        } else {
            return try parseCsv(fileURL: fileURL)
        }
    }

    // MARK: - BIN Parser (Protobuf + COBS)

    /// Parst eine BIN-Datei (OBS Lite Format: COBS-encoded Protobuf)
    private static func parseBin(fileURL: URL) throws -> LocalTrackData {
        let data = try Data(contentsOf: fileURL)

        // Frames sind durch 0x00 getrennt
        let frames = splitFrames(data: data)

        var route: [CLLocationCoordinate2D] = []
        var events: [OvertakeEvent] = []
        var measurementCount = 0

        // Für Überholvorgänge: letzte bekannte Position und Distanz merken
        var lastCoordinate: CLLocationCoordinate2D?
        var lastDistance: Double?

        for frame in frames {
            guard !frame.isEmpty else { continue }

            // COBS dekodieren
            guard let decoded = COBS.decode(frame) else { continue }

            // Protobuf parsen
            let event: Openbikesensor_Event
            do {
                event = try Openbikesensor_Event(serializedBytes: decoded)
            } catch {
                print("LocalTrackParser: Protobuf decode error: \(error)")
                continue
            }

            measurementCount += 1

            // Content auswerten
            switch event.content {
            case .geolocation(let geo):
                // GPS-Koordinate extrahieren
                let lat = geo.latitude
                let lon = geo.longitude

                guard lat != 0, lon != 0,
                      lat >= -90, lat <= 90,
                      lon >= -180, lon <= 180 else { continue }

                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                route.append(coord)
                lastCoordinate = coord

            case .distanceMeasurement(let dm):
                // Distanz in Metern speichern
                let dist = Double(dm.distance)
                if dist > 0 {
                    lastDistance = dist
                }

            case .userInput(let ui):
                // UserInput mit type=overtaker ist ein bestätigter Überholvorgang
                if ui.type == .overtaker, let coord = lastCoordinate {
                    let overtakeEvent = OvertakeEvent(
                        coordinate: coord,
                        distance: lastDistance
                    )
                    events.append(overtakeEvent)
                }

            default:
                break
            }
        }

        let distanceMeters = calculateDistance(route: route)

        return LocalTrackData(
            route: route,
            events: events,
            distanceMeters: distanceMeters,
            measurementCount: measurementCount
        )
    }

    /// Teilt Daten an 0x00-Bytes in einzelne Frames auf
    private static func splitFrames(data: Data) -> [Data] {
        var frames: [Data] = []
        var currentFrame = Data()

        for byte in data {
            if byte == 0x00 {
                if !currentFrame.isEmpty {
                    frames.append(currentFrame)
                    currentFrame = Data()
                }
            } else {
                currentFrame.append(byte)
            }
        }

        // Letzten Frame hinzufügen falls vorhanden
        if !currentFrame.isEmpty {
            frames.append(currentFrame)
        }

        return frames
    }

    // MARK: - CSV Parser (OBS Classic)

    /// Parst eine CSV-Datei und extrahiert Route + Events
    private static func parseCsv(fileURL: URL) throws -> LocalTrackData {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        // Mindestens 2 Zeilen (Metadata + Header) + Daten
        guard lines.count > 2 else {
            return LocalTrackData(route: [], events: [], distanceMeters: 0, measurementCount: 0)
        }

        // Erste Zeile = Metadaten (Key=Value&Key=Value)
        // Zweite Zeile = Header
        // Rest = Daten

        let headerLine = lines[1]
        let headers = headerLine.components(separatedBy: ";")

        // Spaltenindizes finden
        guard let latIndex = headers.firstIndex(of: "Latitude"),
              let lonIndex = headers.firstIndex(of: "Longitude") else {
            // Keine GPS-Spalten gefunden
            return LocalTrackData(route: [], events: [], distanceMeters: 0, measurementCount: 0)
        }

        let confirmedIndex = headers.firstIndex(of: "Confirmed")
        let leftIndex = headers.firstIndex(of: "Left")
        let rightIndex = headers.firstIndex(of: "Right")

        var route: [CLLocationCoordinate2D] = []
        var events: [OvertakeEvent] = []
        var measurementCount = 0

        // Datenzeilen parsen (ab Zeile 3)
        for i in 2..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let fields = line.components(separatedBy: ";")
            guard fields.count > max(latIndex, lonIndex) else { continue }

            measurementCount += 1

            // GPS-Koordinaten extrahieren
            let latStr = fields[latIndex]
            let lonStr = fields[lonIndex]

            guard !latStr.isEmpty, !lonStr.isEmpty,
                  let lat = Double(latStr),
                  let lon = Double(lonStr),
                  lat != 0, lon != 0,
                  lat >= -90, lat <= 90,
                  lon >= -180, lon <= 180 else {
                continue
            }

            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            route.append(coord)

            // Bestätigte Überholvorgänge finden
            if let confIdx = confirmedIndex,
               fields.count > confIdx,
               fields[confIdx] == "1" {

                // Distanz aus Left oder Right extrahieren (welcher kleiner ist)
                var distance: Double? = nil

                if let leftIdx = leftIndex,
                   fields.count > leftIdx,
                   let leftVal = Double(fields[leftIdx]),
                   leftVal > 0 {
                    distance = leftVal / 100.0 // cm -> m
                }

                if let rightIdx = rightIndex,
                   fields.count > rightIdx,
                   let rightVal = Double(fields[rightIdx]),
                   rightVal > 0 {
                    if let existingDist = distance {
                        distance = min(existingDist, rightVal / 100.0)
                    } else {
                        distance = rightVal / 100.0
                    }
                }

                let event = OvertakeEvent(coordinate: coord, distance: distance)
                events.append(event)
            }
        }

        // Distanz berechnen
        let distanceMeters = calculateDistance(route: route)

        return LocalTrackData(
            route: route,
            events: events,
            distanceMeters: distanceMeters,
            measurementCount: measurementCount
        )
    }

    /// Berechnet die Gesamtdistanz einer Route in Metern
    private static func calculateDistance(route: [CLLocationCoordinate2D]) -> Double {
        guard route.count > 1 else { return 0 }

        var total: Double = 0
        for i in 1..<route.count {
            let from = CLLocation(latitude: route[i-1].latitude, longitude: route[i-1].longitude)
            let to = CLLocation(latitude: route[i].latitude, longitude: route[i].longitude)
            total += from.distance(from: to)
        }
        return total
    }
}
