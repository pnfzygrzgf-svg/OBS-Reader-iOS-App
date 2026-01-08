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
            // MARK: - Lock Screen / Banner UI (ohne “Signal vor …”)

            HStack(spacing: 12) {
                // Status
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(context.state.sensorActive ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)

                        Text(context.state.sensorActive ? "Sensor aktiv" : "Kein Signal")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Spacer(minLength: 8)

                // Letzter Abstand
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Letzter Abstand")
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
            .padding(.horizontal)
            .padding(.vertical, 8)
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            // MARK: - Dynamic Island UI (ohne “Signal vor …”)

            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.sensorActive ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)

                        Text("OBS")
                            .font(.caption.weight(.semibold))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let cm = context.state.lastOvertakeCm {
                        Text("\(cm) cm")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.caption.weight(.semibold))
                    }
                }

                // Optional: ganz weglassen oder leer lassen
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
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
    OvertakeActivityAttributes.ContentState(lastOvertakeCm: 123, sensorActive: true, lastPacketAt: Date())
    OvertakeActivityAttributes.ContentState(lastOvertakeCm: nil, sensorActive: false, lastPacketAt: nil)
}
