// OvertakeActivityAttributes.swift

import Foundation
import ActivityKit

struct OvertakeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var lastOvertakeCm: Int?
        var sensorActive: Bool
        var lastPacketAt: Date?
    }

    var sessionId: String
}
