import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Starts tonight's recording and, in the morning, summarizes it and sends the file to the iPhone.
@MainActor
@Observable
final class RecordingController: NSObject {
    private static let planKey = "watchMotion.plan"
    private static let sentKey = "watchMotion.sentPlanStart"

    private let source: any AccelerometerSource
    private let defaults: UserDefaults
    private(set) var plan: RecordingPlan?
    /// Start of the last plan whose recording reached the iPhone's queue, so the morning screen can step aside.
    private(set) var sentPlanStart: Date?
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
        sentPlanStart = defaults.object(forKey: Self.sentKey) as? Date
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    enum Phase: Equatable {
        /// No recording, or the last one was sent.
        case ready
        case recording(RecordingPlan)
        /// The recording ended and hasn't been sent.
        case finished(RecordingPlan)
    }

    func phase(now: Date = .now) -> Phase {
        guard let plan else { return .ready }
        if now < plan.end { return .recording(plan) }
        return sentPlanStart == plan.start ? .ready : .finished(plan)
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
        status = ""
    }

    /// Ends the recording now. Apple's recorder can't be cancelled and keeps sampling to the planned end, but
    /// only the span up to now is read back and sent. A recording stopped within its first minute is dropped.
    func stop(now: Date = .now) {
        guard let plan else { return }
        let stopped = plan.stopped(at: now)
        if stopped.duration < 60 {
            self.plan = nil
            defaults.removeObject(forKey: Self.planKey)
        } else {
            self.plan = stopped
            if let data = try? JSONEncoder().encode(stopped) { defaults.set(data, forKey: Self.planKey) }
        }
        status = ""
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
            sentPlanStart = plan.start
            defaults.set(plan.start, forKey: Self.sentKey)
            status = "Sent to iPhone"
        } catch {
            status = "Could not save the recording: \(error.localizedDescription)"
        }
    }
}

extension RecordingController: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
