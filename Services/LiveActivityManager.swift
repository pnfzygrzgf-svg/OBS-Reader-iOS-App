// LiveActivityManager.swift

import Foundation
import ActivityKit

/// Kein ObservableObject nötig.
/// Wir machen nur die Methoden @MainActor, nicht die ganze Klasse.
final class LiveActivityManager {
    private var activity: Activity<OvertakeActivityAttributes>?

    @MainActor
    func start(
        sessionId: String,
        lastOvertakeCm: Int?,
        sensorActive: Bool,
        lastPacketAt: Date?
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = OvertakeActivityAttributes(sessionId: sessionId)
        let state = OvertakeActivityAttributes.ContentState(
            lastOvertakeCm: lastOvertakeCm,
            sensorActive: sensorActive,
            lastPacketAt: lastPacketAt
        )

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(30))

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // optional logging
        }
    }

    @MainActor
    func update(
        lastOvertakeCm: Int?,
        sensorActive: Bool,
        lastPacketAt: Date?
    ) async {
        guard let activity else { return }

        let state = OvertakeActivityAttributes.ContentState(
            lastOvertakeCm: lastOvertakeCm,
            sensorActive: sensorActive,
            lastPacketAt: lastPacketAt
        )

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(30))
        await activity.update(content)
    }

    @MainActor
    func stop() async {
        guard let activity else { return }
        await activity.end(dismissalPolicy: .immediate)
        self.activity = nil
    }
}
