import Foundation

/// Whether the Watch records movement every night, and the usual night, as the iPhone last sent them. The iPhone
/// takes bed and wake from last night's Watch sleep in Health and sends a default night without it.
struct NightlyMotionSettings: Codable, Sendable, Equatable {
    static let contextKey = "nightlyMotion"
    static let defaultBedMinutes = 22 * 60 + 30
    static let defaultWakeMinutes = 7 * 60

    var enabled = true
    /// Local clock times, in minutes after midnight.
    var bedMinutes = defaultBedMinutes
    var wakeMinutes = defaultWakeMinutes
    /// True when bed and wake came from Watch sleep in Health rather than the default.
    var fromHealth = false

    init(enabled: Bool = true) {
        self.enabled = enabled
    }

    /// The night taken from a slept bed and wake, as local clock times.
    init(enabled: Bool, bed: Date, wake: Date, calendar: Calendar = .current) {
        self.enabled = enabled
        bedMinutes = Self.minutes(bed, calendar)
        wakeMinutes = Self.minutes(wake, calendar)
        fromHealth = true
    }

    private static func minutes(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The WatchConnectivity application context that carries these settings.
    func context() throws -> [String: Any] {
        [Self.contextKey: try JSONEncoder().encode(self)]
    }

    static func decode(context: [String: Any]) -> NightlyMotionSettings? {
        guard let data = context[contextKey] as? Data else { return nil }
        return try? JSONDecoder().decode(NightlyMotionSettings.self, from: data)
    }
}

/// When the Watch starts a night's recording on its own, and how it reads the night back a span at a time.
/// Apple's recorder takes at most 12 hours per request and can't be scheduled ahead, so the Watch asks for each
/// night when a wake lands inside it: a background refresh it schedules for the night's start, a later refresh,
/// the app opening, or new settings from the iPhone.
enum NightlyCapture {
    /// Recording starts this long before the usual bedtime and runs this long past the usual wake.
    static let lead: TimeInterval = 30 * 60
    static let trail: TimeInterval = 60 * 60
    /// A night with less than this left isn't started.
    static let minimumRemaining: TimeInterval = 60 * 60
    /// The recorder can hold readings back for up to 3 minutes; a span is read once this has passed since it ended.
    static let settle: TimeInterval = 10 * 60
    /// An empty span is read again until this long after it ends, then taken as no data.
    static let emptyGrace: TimeInterval = 30 * 60
    /// Spans end on multiples of this in Unix time, a multiple of the 2 s bins, so no bin straddles two spans.
    static let span: TimeInterval = 10 * 60
    /// How long the system keeps what it recorded.
    static let retention: TimeInterval = 3 * 86400
    /// Wakes while a night records, to summarize what has settled and to re-arm after a restart.
    static let recordingWakeInterval: TimeInterval = 60 * 60
    /// Wakes after a skip that may clear, such as Low Power Mode being turned off.
    static let retryInterval: TimeInterval = 30 * 60
    /// A re-arm with less than this left isn't worth a request.
    static let minimumRearm: TimeInterval = 5 * 60

    /// The night that contains `now` or, failing that, the next one: from the usual bed less `lead` to the usual
    /// wake plus `trail`, shortened at the start to fit one 12-hour request.
    static func window(around now: Date, settings: NightlyMotionSettings, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        for offset in -1...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let night = window(on: day, settings: settings, calendar: calendar), night.end > now else { continue }
            return night
        }
        return DateInterval(start: now, duration: 0)
    }

    /// The night that starts at the usual bedtime on `day`.
    static func window(on day: Date, settings: NightlyMotionSettings, calendar: Calendar = .current) -> DateInterval? {
        func at(_ minutes: Int, _ day: Date) -> Date? {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
        }
        let wakeDay = settings.wakeMinutes > settings.bedMinutes ? day : calendar.date(byAdding: .day, value: 1, to: day)
        guard let bed = at(settings.bedMinutes, day), let wakeDay, let wake = at(settings.wakeMinutes, wakeDay) else { return nil }
        let end = wake.addingTimeInterval(trail)
        let start = max(bed.addingTimeInterval(-lead), end.addingTimeInterval(-RecordingPlan.maximumDuration))
        return DateInterval(start: start, end: end)
    }

    enum Action: Equatable, Sendable {
        case none
        /// Ask the recorder for this plan and keep it as tonight's.
        case arm(RecordingPlan)
        /// Ask the recorder again for the rest of tonight's plan, which a restart may have ended.
        case rearm(RecordingPlan)
        case skip(SkipReason)
    }

    enum SkipReason: String, Sendable {
        case lowPower, notAuthorized
    }

    struct Conditions: Sendable {
        var lowPower = false
        /// Motion & Fitness allows recording now; in the background that means already authorized.
        var canRecord = true
        /// When the Watch last started up; a recording requested before it may have ended with the restart.
        var bootedAt = Date.distantPast
    }

    struct Decision: Equatable, Sendable {
        var action: Action
        /// When to wake next; nil when nothing is scheduled.
        var wake: Date?
    }

    /// What to do at a wake: arm tonight's recording once it is due and no recording already overlaps it, re-arm
    /// one requested before a restart, skip in Low Power Mode or without permission, and when to wake next.
    static func decide(now: Date, settings: NightlyMotionSettings, plan: RecordingPlan?, armedAt: Date?,
                       conditions: Conditions, calendar: Calendar = .current) -> Decision {
        guard settings.enabled else { return Decision(action: .none, wake: nil) }
        let night = window(around: now, settings: settings, calendar: calendar)
        let next = window(around: night.end, settings: settings, calendar: calendar)
        if let plan, plan.start < night.end, plan.end > night.start {
            guard now < plan.end else { return Decision(action: .none, wake: next.start) }
            let restarted = armedAt.map { conditions.bootedAt > $0 } ?? false
            let rearm = restarted && plan.end.timeIntervalSince(now) >= minimumRearm
            return Decision(action: rearm ? .rearm(plan) : .none, wake: recordingWake(now: now, end: plan.end))
        }
        if now < night.start { return Decision(action: .none, wake: night.start) }
        guard night.end.timeIntervalSince(now) >= minimumRemaining else { return Decision(action: .none, wake: next.start) }
        if conditions.lowPower { return Decision(action: .skip(.lowPower), wake: now.addingTimeInterval(retryInterval)) }
        guard conditions.canRecord else { return Decision(action: .skip(.notAuthorized), wake: next.start) }
        return Decision(action: .arm(RecordingPlan(start: now, end: night.end)), wake: recordingWake(now: now, end: night.end))
    }

    /// Hourly while recording, then once the end has settled, to read the battery and finish the night.
    private static func recordingWake(now: Date, end: Date) -> Date {
        min(end.addingTimeInterval(settle), now.addingTimeInterval(recordingWakeInterval))
    }
}

/// A night summarized a span at a time, so background wakes of a few seconds each can work through it. Spans end
/// on Unix multiples of `NightlyCapture.span`, so the bins equal those of summarizing the whole night at once.
struct NightProgress: Codable, Sendable, Equatable {
    var plan: RecordingPlan
    /// Everything before this is summarized.
    var cursor: Date
    var bins = WatchMotionFile.Bins(meanX: [], meanY: [], meanZ: [])

    init(plan: RecordingPlan) {
        self.plan = plan
        cursor = plan.start
    }

    var isComplete: Bool { cursor >= plan.end }

    /// The next span to read, once the recorder has had time to hand it over.
    func nextSpan(now: Date) -> DateInterval? {
        guard cursor < plan.end else { return nil }
        let boundary = ((cursor.timeIntervalSince1970 / NightlyCapture.span).rounded(.down) + 1) * NightlyCapture.span
        let end = min(Date(timeIntervalSince1970: boundary), plan.end)
        guard end.addingTimeInterval(NightlyCapture.settle) <= now else { return nil }
        return DateInterval(start: cursor, end: end)
    }

    /// The interval to ask the recorder for: it returns (from, to], so asking from a second early keeps a reading
    /// exactly at the span's start.
    static func query(for span: DateInterval) -> DateInterval {
        DateInterval(start: span.start.addingTimeInterval(-1), end: span.end)
    }

    /// Adds a span's readings in [start, end). Returns false and leaves the span to read again when it is empty but
    /// recent enough that the recorder may still hand readings over.
    @discardableResult
    mutating func add(_ samples: [MotionSample], for span: DateInterval, now: Date) -> Bool {
        let from = span.start.timeIntervalSince1970, to = span.end.timeIntervalSince1970
        let inSpan = samples.filter { $0.time >= from && $0.time < to }
        if inSpan.isEmpty, now < span.end.addingTimeInterval(NightlyCapture.emptyGrace) { return false }
        bins.append(MotionSummarizer.summarize(inSpan))
        cursor = span.end
        return true
    }

    func file(timeZone: TimeZone, device: String) -> WatchMotionFile {
        MotionSummarizer.file(bins: bins, from: plan.start, to: plan.end, timeZone: timeZone, device: device)
    }
}

/// How a night's recording went on the Watch. It travels with the file as transfer metadata, not inside it, so the
/// `watch-motion-v2` format sleepypod/training reads stays the same. The battery cost covers the whole Watch.
struct WatchMotionCapture: Codable, Sendable, Equatable {
    static let metadataKey = "capture"

    var recordedFromMs: Int64
    /// Started by the nightly schedule rather than the Record button.
    var automatic: Bool
    var armedAt: Date
    /// Requests made again after a restart.
    var rearms = 0
    var batteryStart: Battery?
    /// The last reading off the charger up to the night's end.
    var batteryEnd: Battery?

    struct Battery: Codable, Sendable, Equatable {
        /// 0–1.
        var level: Double
        var charging: Bool
        var at: Date
    }

    init(plan: RecordingPlan, automatic: Bool, armedAt: Date, battery: Battery?) {
        recordedFromMs = Int64((plan.start.timeIntervalSince1970 * 1000).rounded())
        self.automatic = automatic
        self.armedAt = armedAt
        batteryStart = battery
    }

    /// Keeps a reading as the end while the night runs and the Watch is off the charger.
    mutating func note(_ battery: Battery?, planEnd: Date) {
        guard let battery, !battery.charging, battery.at >= armedAt,
              battery.at <= planEnd.addingTimeInterval(NightlyCapture.settle) else { return }
        batteryEnd = battery
    }

    /// Battery fraction used per hour between start and end; nil when either is missing, the start was on the
    /// charger, or they are less than an hour apart.
    var batteryPerHour: Double? {
        guard let start = batteryStart, let end = batteryEnd, !start.charging else { return nil }
        let hours = end.at.timeIntervalSince(start.at) / 3600
        guard hours >= 1 else { return nil }
        return (start.level - end.level) / hours
    }

    /// "Nightly · battery 84% → 61% over 8.2 h", for the recording's row on the iPhone.
    var summary: String {
        var parts = [automatic ? "Nightly" : "Manual"]
        if let start = batteryStart, let end = batteryEnd {
            let hours = end.at.timeIntervalSince(start.at) / 3600
            parts.append("battery \(Self.percent(start.level)) → \(Self.percent(end.level)) over "
                         + hours.formatted(.number.precision(.fractionLength(1))) + " h")
        } else if let start = batteryStart {
            parts.append("battery \(Self.percent(start.level)) at start")
        }
        if rearms > 0 { parts.append("re-armed \(rearms)×") }
        return parts.joined(separator: " · ")
    }

    private static func percent(_ level: Double) -> String { "\(Int((level * 100).rounded()))%" }

    func metadata() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(metadata: [String: Any]?) -> WatchMotionCapture? {
        guard let data = metadata?[metadataKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchMotionCapture.self, from: data)
    }
}
