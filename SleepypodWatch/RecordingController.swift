import Foundation
import Observation
import OSLog
import WatchConnectivity
import WatchKit

/// Starts tonight's recording and, in the morning, summarizes it and sends the file to the iPhone. With nightly
/// recording on (the default, set on the iPhone) it does both on its own: see `NightlyCapture`.
@MainActor
@Observable
final class RecordingController: NSObject {
    private static let planKey = "watchMotion.plan"
    private static let sentKey = "watchMotion.sentPlanStart"
    private static let nightlyKey = "watchMotion.nightly"
    private static let nightsKey = "watchMotion.nights"
    private nonisolated static let log = Logger(subsystem: "com.jonathanng.com.ios.sleepypod.watchkitapp", category: "motion")
    /// Background refreshes get a few seconds; spans are read until this much has passed, then the next wake goes on.
    private static let backgroundBudget: TimeInterval = 4
    private static let foregroundBudget: TimeInterval = 20

    private let source: any AccelerometerSource
    private let defaults: UserDefaults
    private let automatic: Bool
    private let scheduleWake: @MainActor (Date) -> Void
    private let progressURL: URL
    private(set) var plan: RecordingPlan?
    /// Start of the last plan whose recording reached the iPhone's queue, so the morning screen can step aside.
    private(set) var sentPlanStart: Date?
    private(set) var status = ""
    private(set) var busy = false
    var hours = 9.0
    var includeRaw = false
    /// Whether to record every night and when, as the iPhone last sent it.
    private(set) var nightly: NightlyMotionSettings
    /// Why tonight's recording hasn't started, while that may still change.
    private(set) var skipped: NightlyCapture.SkipReason?
    /// Recent recordings and how each went, oldest first; unsent ones are summarized and sent in turn.
    private var nights: [Night]
    private var working = false

    struct Night: Codable, Equatable {
        var plan: RecordingPlan
        var capture: WatchMotionCapture
        var sent = false
    }

    init(source: any AccelerometerSource = CoreMotionAccelerometer(), defaults: UserDefaults = .standard,
         automatic: Bool = true, scheduleWake: @escaping @MainActor (Date) -> Void = RecordingController.scheduleRefresh(at:)) {
        self.source = source
        self.defaults = defaults
        self.automatic = automatic
        self.scheduleWake = scheduleWake
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        progressURL = support.appendingPathComponent("watch-motion-progress.json")
        nightly = defaults.data(forKey: Self.nightlyKey).flatMap { try? JSONDecoder().decode(NightlyMotionSettings.self, from: $0) }
            ?? NightlyMotionSettings()
        nights = defaults.data(forKey: Self.nightsKey).flatMap { try? JSONDecoder().decode([Night].self, from: $0) } ?? []
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

    /// The nightly line under the Record button: when tonight starts, or why it waits.
    func nightlyNote(now: Date = .now) -> String? {
        guard automatic, nightly.enabled else { return nil }
        switch skipped {
        case .lowPower: return "Low Power Mode is on, so tonight's recording waits."
        case .notAuthorized: return "Open sleepypod at bedtime once to allow Motion & Fitness."
        case nil:
            let night = NightlyCapture.window(around: now, settings: nightly)
            return "Records every night from \(night.start.formatted(date: .omitted, time: .shortened))"
        }
    }

    func recordTonight(now: Date = .now) {
        guard canRecord else {
            status = availability
            return
        }
        arm(RecordingPlan(start: now, hours: hours), automatic: false, now: now)
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
            nights.removeAll { $0.plan.start == plan.start }
        } else {
            self.plan = stopped
            if let data = try? JSONEncoder().encode(stopped) { defaults.set(data, forKey: Self.planKey) }
            if let index = nights.firstIndex(where: { $0.plan.start == plan.start }) { nights[index].plan = stopped }
            if var progress = loadProgress(), progress.plan.start == plan.start {
                progress.plan = stopped
                saveProgress(progress)
            }
        }
        saveNights()
        status = ""
    }

    /// Shows a line from elsewhere, such as what the iPhone sent on to the pod.
    func note(_ line: String) {
        status = line
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
        let file = await Task.detached(priority: .userInitiated) { [device = Self.device] in
            MotionSummarizer.file(samples: source.samples(in: interval), from: interval.start, to: interval.end,
                                  timeZone: .current, device: device, includeRaw: includeRaw)
        }.value
        guard file.bins.count > 0 else {
            status = "The Watch kept no readings for this night."
            return
        }
        if transfer(file, capture: nights.first { $0.plan.start == plan.start }?.capture) {
            markSent(plan)
            status = "Sent to iPhone"
        }
    }

    // MARK: Nightly

    /// Starts tonight's recording when it is due, works through recorded nights and sends finished ones, then asks
    /// to be woken for the next step. Runs at launch, in the foreground, from background refreshes and when the
    /// iPhone sends new settings.
    func nightlyWake(foreground: Bool) async {
        guard automatic, !working else { return }
        working = true
        defer { working = false }
        let now = Date.now
        nights.removeAll { $0.plan.end < now.addingTimeInterval(-NightlyCapture.retention) }
        let latest = plan.flatMap { plan in nights.last { $0.plan.start == plan.start } }
        let authorized = foreground ? canRecord : source.isAvailable && source.authorization == .authorized
        let conditions = NightlyCapture.Conditions(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, canRecord: authorized,
                                                   bootedAt: now.addingTimeInterval(-ProcessInfo.processInfo.systemUptime))
        let decision = NightlyCapture.decide(now: now, settings: nightly, plan: plan, armedAt: latest?.capture.armedAt,
                                             conditions: conditions)
        skipped = nil
        switch decision.action {
        case .none: break
        case .arm(let tonight):
            arm(tonight, automatic: true, now: now)
        case .rearm(let tonight):
            source.record(duration: tonight.end.timeIntervalSince(now))
            if let index = nights.firstIndex(where: { $0.plan.start == tonight.start }) {
                nights[index].capture.rearms += 1
                nights[index].capture.armedAt = now
            }
            Self.log.notice("Re-armed tonight's recording after a restart, \(Int(tonight.end.timeIntervalSince(now) / 60)) min left")
        case .skip(let reason):
            skipped = reason
            Self.log.notice("Skipped arming tonight: \(reason.rawValue, privacy: .public)")
        }
        let battery = Self.battery(now: now)
        for index in nights.indices where !nights[index].sent {
            nights[index].capture.note(battery, planEnd: nights[index].plan.end)
        }
        saveNights()
        if nightly.enabled, !includeRaw {
            await workThroughNights(until: now.addingTimeInterval(foreground ? Self.foregroundBudget : Self.backgroundBudget))
        }
        var wake = decision.wake
        if nightly.enabled, nights.contains(where: { !$0.sent && $0.plan.start < now }) {
            // Hourly while a night records; sooner once a finished night is waiting to be read.
            let pending = nights.contains { !$0.sent && $0.plan.end <= now } ? NightlyCapture.settle : NightlyCapture.recordingWakeInterval
            wake = min(wake ?? .distantFuture, now.addingTimeInterval(pending))
        }
        if let wake { scheduleWake(max(wake, now.addingTimeInterval(60))) }
    }

    /// Applies settings from the iPhone and reschedules around them.
    func apply(_ settings: NightlyMotionSettings) async {
        guard settings != nightly else { return }
        nightly = settings
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.nightlyKey) }
        Self.log.notice("Nightly recording \(settings.enabled ? "on" : "off", privacy: .public), bed \(settings.bedMinutes) wake \(settings.wakeMinutes)")
        await nightlyWake(foreground: false)
    }

    private func arm(_ next: RecordingPlan, automatic: Bool, now: Date) {
        source.record(duration: next.duration)
        plan = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.planKey) }
        let battery = Self.battery(now: now)
        nights.append(Night(plan: next, capture: WatchMotionCapture(plan: next, automatic: automatic, armedAt: now, battery: battery)))
        saveNights()
        let level = battery.map { "\(Int(($0.level * 100).rounded()))%" } ?? "unknown"
        Self.log.notice("Armed \(automatic ? "nightly" : "manual", privacy: .public) recording for \(Int(next.duration / 60)) min, battery \(level, privacy: .public)")
    }

    /// Summarizes unsent nights oldest first, a settled span at a time, saving progress after each span so a wake
    /// cut short loses at most one. A finished night is queued for the iPhone.
    private func workThroughNights(until deadline: Date) async {
        while let night = nights.first(where: { !$0.sent && $0.plan.start < Date.now }) {
            var progress = loadProgress().flatMap { $0.plan == night.plan ? $0 : nil } ?? NightProgress(plan: night.plan)
            while !progress.isComplete, Date.now < deadline, !Task.isCancelled, let span = progress.nextSpan(now: .now) {
                let source = source, query = NightProgress.query(for: span)
                let samples = await Task.detached(priority: .utility) { source.samples(in: query) }.value
                guard progress.add(samples, for: span, now: .now) else { break }
                saveProgress(progress)
            }
            guard progress.isComplete, await sessionActivated() else { return }
            finish(night, progress: progress)
        }
    }

    /// A background launch activates the session moments before it is needed; a file queued before then is lost.
    private func sessionActivated() async -> Bool {
        let session = WCSession.default
        for _ in 0..<20 where session.activationState != .activated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return session.activationState == .activated
    }

    private func finish(_ night: Night, progress: NightProgress) {
        let file = progress.file(timeZone: .current, device: Self.device)
        if file.bins.count == 0 {
            Self.log.notice("No readings kept for the night from \(night.plan.start.formatted(.iso8601), privacy: .public)")
            markSent(night.plan)
        } else if transfer(file, capture: night.capture) {
            markSent(night.plan)
            status = "Sent to iPhone"
            let used = night.capture.batteryPerHour.map { "\(($0 * 100).formatted(.number.precision(.fractionLength(1))))%/h" } ?? "unmeasured"
            Self.log.notice("Sent \(file.bins.count) bins; battery \(used, privacy: .public)")
        }
        try? FileManager.default.removeItem(at: progressURL)
    }

    private func transfer(_ file: WatchMotionFile, capture: WatchMotionCapture?) -> Bool {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            try file.encoded().write(to: url, options: .atomic)
            var metadata: [String: Any] = ["kind": "watch-motion", "version": file.version]
            if let data = capture?.metadata() { metadata[WatchMotionCapture.metadataKey] = data }
            WCSession.default.transferFile(url, metadata: metadata)
            return true
        } catch {
            status = "Could not save the recording: \(error.localizedDescription)"
            return false
        }
    }

    private func markSent(_ sent: RecordingPlan) {
        if let index = nights.firstIndex(where: { $0.plan.start == sent.start }) { nights[index].sent = true }
        saveNights()
        if plan?.start == sent.start {
            sentPlanStart = sent.start
            defaults.set(sent.start, forKey: Self.sentKey)
        }
    }

    private func saveNights() {
        if let data = try? JSONEncoder().encode(nights) { defaults.set(data, forKey: Self.nightsKey) }
    }

    private func loadProgress() -> NightProgress? {
        (try? Data(contentsOf: progressURL)).flatMap { try? JSONDecoder().decode(NightProgress.self, from: $0) }
    }

    private func saveProgress(_ progress: NightProgress) {
        try? FileManager.default.createDirectory(at: progressURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(progress).write(to: progressURL, options: .atomic)
    }

    private static var device: String {
        WKInterfaceDevice.current().model + " · watchOS " + WKInterfaceDevice.current().systemVersion
    }

    private static func battery(now: Date) -> WatchMotionCapture.Battery? {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        guard device.batteryLevel >= 0 else { return nil }
        return WatchMotionCapture.Battery(level: Double(device.batteryLevel),
                                          charging: device.batteryState == .charging || device.batteryState == .full, at: now)
    }

    /// Only one background refresh can be pending; scheduling replaces it.
    static func scheduleRefresh(at date: Date) {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date, userInfo: nil) { error in
            if let error { Self.log.error("Couldn't schedule a background refresh: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

extension RecordingController: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let settings = NightlyMotionSettings.decode(context: session.receivedApplicationContext)
        Task { @MainActor in
            if let settings { await self.apply(settings) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let settings = NightlyMotionSettings.decode(context: applicationContext) else { return }
        Task { @MainActor in await self.apply(settings) }
    }
}
