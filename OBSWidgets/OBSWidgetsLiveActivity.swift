//
//  OBSWidgetsLiveActivity.swift
//  OBSWidgets
//

import ActivityKit
import WidgetKit
import SwiftUI

struct OBSWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OvertakeActivityAttributes.self) { context in
            // MARK: - Lock Screen / Banner UI

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // Status + Timer
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(context.state.sensorActive ? Color.green : Color.gray)
                                .frame(width: 10, height: 10)

                            Text(context.state.sensorActive ? "Aufnahme" : "Kein Signal")
                                .font(.subheadline.weight(.semibold))
                        }

                        // Aufnahmezeit
                        if let startTime = context.state.recordingStartTime {
                            Text(startTime, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    // Letzter Abstand
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Abstand")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let cm = context.state.lastOvertakeCm {
                            Text("\(cm) cm")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                        } else {
                            Text("—")
                                .font(.title3.weight(.semibold))
                        }
                    }
                }

                // Statistik-Zeile
                HStack(spacing: 16) {
                    Label("\(context.state.overtakeCount)", systemImage: "car.side")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(String(format: "%.1f km", context.state.distanceMeters / 1000.0), systemImage: "location")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            // MARK: - Dynamic Island UI

            DynamicIsland {
                // Expanded Leading: Status + Timer
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(context.state.sensorActive ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)

                            Text("OBS")
                                .font(.caption.weight(.semibold))
                        }

                        if let startTime = context.state.recordingStartTime {
                            Text(startTime, style: .timer)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Expanded Trailing: Abstand
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let cm = context.state.lastOvertakeCm {
                            Text("\(cm) cm")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        } else {
                            Text("—")
                                .font(.caption.weight(.semibold))
                        }

                        Text("\(context.state.overtakeCount) Überholungen")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Expanded Bottom: Distanz
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(
                            String(format: "%.1f km", context.state.distanceMeters / 1000.0),
                            systemImage: "location"
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Spacer()
                    }
                }

            } compactLeading: {
                Circle()
                    .fill(context.state.sensorActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

            } compactTrailing: {
                if let cm = context.state.lastOvertakeCm {
                    Text("\(cm)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.caption.weight(.semibold))
                }

            } minimal: {
                Circle()
                    .fill(context.state.sensorActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#Preview("Live Activity", as: .content, using: OvertakeActivityAttributes(sessionId: "preview")) {
    OBSWidgetsLiveActivity()
} contentStates: {
    OvertakeActivityAttributes.ContentState(
        lastOvertakeCm: 123,
        sensorActive: true,
        lastPacketAt: Date(),
        recordingStartTime: Date(),
        overtakeCount: 5,
        distanceMeters: 2340.0
    )
    OvertakeActivityAttributes.ContentState(
        lastOvertakeCm: nil,
        sensorActive: false,
        lastPacketAt: nil,
        recordingStartTime: nil,
        overtakeCount: 0,
        distanceMeters: 0.0
    )
}
