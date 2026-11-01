import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Starts tonight's recording and, in the morning, summarizes it and sends the file to the iPhone.
@MainActor
@Observable
final class RecordingController: NSObject {
    private static let planKey = "watchMotion.plan"

    private let source: any AccelerometerSource
    private let defaults: UserDefaults
    private(set) var plan: RecordingPlan?
    private(set) var status = ""
    private(set) var busy = false
    var hours = 9.0
    var includeRaw = false

    init(source: any AccelerometerSource = CoreMotionAccelerometer(), defaults: UserDefaults = .standard) {
        self.source = source
        self.defaults = defaults
        super.init()
        if let data = defaults.data(forKey: Self.planKey) {
            plan = try? JSONDecoder().decode(RecordingPlan.self, from: data)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var availability: String {
        guard source.isAvailable else { return "Recording isn't available on this Watch." }
        switch source.authorization {
        case .denied, .restricted: return "Allow Motion & Fitness for sleepypod in the Watch's Settings."
        case .notDetermined, .authorized: return ""
        }
    }

    /// Recording needs the sensor and Motion & Fitness permission (or a prompt still to come).
    var canRecord: Bool {
        guard source.isAvailable else { return false }
        switch source.authorization {
        case .denied, .restricted: return false
        case .notDetermined, .authorized: return true
        }
    }

    func recordTonight(now: Date = .now) {
        guard canRecord else {
            status = availability
            return
        }
        let next = RecordingPlan(start: now, hours: hours)
        source.record(duration: next.duration)
        plan = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.planKey) }
        status = "Recording until \(next.end.formatted(date: .omitted, time: .shortened)). You can close the app."
    }

    /// Reads what the system kept, summarizes it and queues it for the iPhone; WatchConnectivity retries delivery.
    func send(now: Date = .now) async {
        guard let plan, let interval = plan.readableInterval(now: now) else {
            status = "Nothing recorded yet."
            return
        }
        busy = true
        defer { busy = false }
        let source = source, includeRaw = includeRaw
        let device = WKInterfaceDevice.current().model + " · watchOS " + WKInterfaceDevice.current().systemVersion
        let file = await Task.detached(priority: .userInitiated) {
            MotionSummarizer.file(samples: source.samples(in: interval), from: interval.start, to: interval.end,
                                  timeZone: .current, device: device, includeRaw: includeRaw)
        }.value
        guard file.bins.count > 0 else {
            status = "The Watch kept no readings for this night."
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            try file.encoded().write(to: url, options: .atomic)
            WCSession.default.transferFile(url, metadata: ["kind": "watch-motion", "version": file.version])
            status = "Sent \(file.bins.count) bins to the iPhone."
        } catch {
            status = "Could not save the recording: \(error.localizedDescription)"
        }
    }
}

extension RecordingController: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
