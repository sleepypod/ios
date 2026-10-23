import CoreMotion
import Foundation

enum MotionAuthorization: Sendable {
    case notDetermined, denied, restricted, authorized
}

/// The recorder behind a protocol, so the controller can be exercised without hardware.
protocol AccelerometerSource: Sendable {
    var isAvailable: Bool { get }
    var authorization: MotionAuthorization { get }
    /// Asks the system to record in the background; the app need not stay open.
    func record(duration: TimeInterval)
    /// Readings for an interval the system kept. Slow for a whole night: call off the main actor.
    func samples(in interval: DateInterval) -> [MotionSample]
}

struct CoreMotionAccelerometer: AccelerometerSource {
    var isAvailable: Bool { CMSensorRecorder.isAccelerometerRecordingAvailable() }

    var authorization: MotionAuthorization {
        switch CMSensorRecorder.authorizationStatus() {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    func record(duration: TimeInterval) {
        CMSensorRecorder().recordAccelerometer(forDuration: duration)
    }

    func samples(in interval: DateInterval) -> [MotionSample] {
        guard let list = CMSensorRecorder().accelerometerData(from: interval.start, to: interval.end) else { return [] }
        var out: [MotionSample] = []
        // CMRecordedAccelerometerData.timestamp is seconds since boot; startDate is the wall-clock time.
        for case let reading as CMRecordedAccelerometerData in list {
            let a = reading.acceleration
            out.append(MotionSample(time: reading.startDate.timeIntervalSince1970, x: a.x, y: a.y, z: a.z))
        }
        return out
    }
}

extension CMSensorDataList: @retroactive Sequence {
    public func makeIterator() -> NSFastEnumerationIterator { NSFastEnumerationIterator(self) }
}
