// SPDX-License-Identifier: GPL-3.0-or-later

// OvertakeActivityAttributes.swift

import Foundation
import ActivityKit

struct OvertakeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var lastOvertakeCm: Int?
        var sensorActive: Bool
        var lastPacketAt: Date?

        // Erweiterte Statistiken für Live Activity
        var recordingStartTime: Date?
        var overtakeCount: Int
        var distanceMeters: Double

        init(
            lastOvertakeCm: Int? = nil,
            sensorActive: Bool = false,
            lastPacketAt: Date? = nil,
            recordingStartTime: Date? = nil,
            overtakeCount: Int = 0,
            distanceMeters: Double = 0.0
        ) {
            self.lastOvertakeCm = lastOvertakeCm
            self.sensorActive = sensorActive
            self.lastPacketAt = lastPacketAt
            self.recordingStartTime = recordingStartTime
            self.overtakeCount = overtakeCount
            self.distanceMeters = distanceMeters
        }
    }

    var sessionId: String
}
