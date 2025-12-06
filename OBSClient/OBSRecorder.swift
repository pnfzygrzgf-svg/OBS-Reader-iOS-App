import Foundation
import CoreLocation

final class OBSRecorder {

    private let binWriter = OBSFileWriter()
    private let csvWriter = OBSCSVWriter()

    private(set) var isRecording = false

    func start() {
        guard !isRecording else { return }
        isRecording = true

        binWriter.startSession()
        csvWriter.startSession()
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false

        binWriter.finishSession()
        csvWriter.finishSession()
    }

    /// vom LocationManager weiterreichen
    func updateLocation(_ location: CLLocation) {
        csvWriter.updateLocation(location)
    }

    /// immer dann aufrufen, wenn du ein neues OBS-Event bekommen hast
    func handleMeasurement(
        rawCOBSFrame: Data,
        timestamp: Date,
        leftCm: Int?,
        rightCm: Int?,
        comment: String? = nil
    ) {
        guard isRecording else { return }

        // .bin
        binWriter.write(rawCOBSFrame)

        // .csv
        csvWriter.appendMeasurement(
            timestamp: timestamp,
            leftCm: leftCm,
            rightCm: rightCm,
            comment: comment
        )
    }
}
