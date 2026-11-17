import Testing
import Foundation
@testable import Sleepypod

/// Nightly Watch movement: which night to record, when the Watch arms, skips and re-arms the recorder, how a night
/// is read back a span at a time, and the capture notes that carry battery cost to the iPhone.
@Suite("Nightly Watch movement")
struct NightlyCaptureTests {
    private static let zone = TimeZone(identifier: "America/Los_Angeles")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        return calendar
    }

    private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func settings(bed: Int, wake: Int, enabled: Bool = true) -> NightlyMotionSettings {
        var settings = NightlyMotionSettings(enabled: enabled)
        settings.bedMinutes = bed
        settings.wakeMinutes = wake
        return settings
    }

    private func still(_ t: Double) -> MotionSample { MotionSample(time: t, x: 0, y: 0, z: 1) }

    // MARK: Window

    @Test func defaultNightRunsFromBeforeBedToAfterWake() {
        let night = NightlyCapture.window(around: local(2026, 11, 15, 12), settings: NightlyMotionSettings(), calendar: calendar)
        #expect(night.start == local(2026, 11, 15, 22))
        #expect(night.end == local(2026, 11, 16, 8))
    }

    @Test func windowIsTheNightInProgressThenTheNextOne() {
        let defaults = NightlyMotionSettings()
        let morning = NightlyCapture.window(around: local(2026, 11, 16, 3), settings: defaults, calendar: calendar)
        #expect(morning.start == local(2026, 11, 15, 22))
        let afterEnd = NightlyCapture.window(around: local(2026, 11, 16, 8, 1), settings: defaults, calendar: calendar)
        #expect(afterEnd.start == local(2026, 11, 16, 22))
    }

    @Test func longNightKeepsTheWakeAndFitsOneRequest() {
        // Bed 20:00, wake 09:00: 14 h with lead and trail, cut at the start to the recorder's 12 h.
        let night = NightlyCapture.window(around: local(2026, 11, 15, 12), settings: settings(bed: 20 * 60, wake: 9 * 60),
                                          calendar: calendar)
        #expect(night.end == local(2026, 11, 16, 10))
        #expect(night.duration == RecordingPlan.maximumDuration)
    }

    @Test func nightAfterMidnightStaysOnOneDay() {
        let night = NightlyCapture.window(around: local(2026, 11, 15, 12), settings: settings(bed: 60, wake: 9 * 60), calendar: calendar)
        #expect(night.start == local(2026, 11, 16, 0, 30))
        #expect(night.end == local(2026, 11, 16, 10))
    }

    @Test func daylightSavingNightKeepsLocalClockTimes() {
        // US clocks fall back at 02:00 on 2026-11-01: the night is an hour longer in absolute time.
        let night = NightlyCapture.window(around: local(2026, 10, 31, 12), settings: NightlyMotionSettings(), calendar: calendar)
        #expect(night.start == local(2026, 10, 31, 22))
        #expect(night.end == local(2026, 11, 1, 8))
        #expect(night.duration == 11 * 3600)
    }

    // MARK: Decide

    private let ready = NightlyCapture.Conditions()

    @Test func beforeTheNightItWaitsForTheStart() {
        let decision = NightlyCapture.decide(now: local(2026, 11, 15, 18), settings: NightlyMotionSettings(), plan: nil, armedAt: nil,
                                             conditions: ready, calendar: calendar)
        #expect(decision == .init(action: .none, wake: local(2026, 11, 15, 22)))
    }

    @Test func insideTheNightItArmsToTheEndAndWakesHourly() {
        let now = local(2026, 11, 15, 22, 5)
        let decision = NightlyCapture.decide(now: now, settings: NightlyMotionSettings(), plan: nil, armedAt: nil,
                                             conditions: ready, calendar: calendar)
        let plan = RecordingPlan(start: now, end: local(2026, 11, 16, 8))
        #expect(decision.action == .arm(plan))
        #expect(plan.duration == 9 * 3600 + 55 * 60)
        #expect(decision.wake == now.addingTimeInterval(3600))
    }

    @Test func aLateWakeStillArmsTheRestButNotTheLastHour() {
        let late = NightlyCapture.decide(now: local(2026, 11, 16, 6), settings: NightlyMotionSettings(), plan: nil, armedAt: nil,
                                         conditions: ready, calendar: calendar)
        #expect(late.action == .arm(RecordingPlan(start: local(2026, 11, 16, 6), end: local(2026, 11, 16, 8))))
        let tooLate = NightlyCapture.decide(now: local(2026, 11, 16, 7, 30), settings: NightlyMotionSettings(), plan: nil,
                                            armedAt: nil, conditions: ready, calendar: calendar)
        #expect(tooLate == .init(action: .none, wake: local(2026, 11, 16, 22)))
    }

    @Test func aRecordingTonightIsLeftAloneUnlessTheWatchRestarted() {
        let armed = local(2026, 11, 15, 22)
        let plan = RecordingPlan(start: armed, end: local(2026, 11, 16, 8))
        let now = local(2026, 11, 16, 2)
        let running = NightlyCapture.decide(now: now, settings: NightlyMotionSettings(), plan: plan, armedAt: armed,
                                            conditions: ready, calendar: calendar)
        #expect(running == .init(action: .none, wake: now.addingTimeInterval(3600)))

        let restarted = NightlyCapture.Conditions(bootedAt: local(2026, 11, 16, 1))
        let rearm = NightlyCapture.decide(now: now, settings: NightlyMotionSettings(), plan: plan, armedAt: armed,
                                          conditions: restarted, calendar: calendar)
        #expect(rearm.action == .rearm(plan))
        // The re-armed request counts as armed after the restart, so the next wake leaves it alone.
        let after = NightlyCapture.decide(now: now.addingTimeInterval(600), settings: NightlyMotionSettings(), plan: plan,
                                          armedAt: now, conditions: restarted, calendar: calendar)
        #expect(after.action == .none)
        let nearEnd = NightlyCapture.decide(now: local(2026, 11, 16, 7, 57), settings: NightlyMotionSettings(), plan: plan,
                                            armedAt: armed, conditions: restarted, calendar: calendar)
        #expect(nearEnd == .init(action: .none, wake: local(2026, 11, 16, 8, 10)))
    }

    @Test func aRecordingStoppedTonightIsNotStartedAgain() {
        let plan = RecordingPlan(start: local(2026, 11, 15, 22), end: local(2026, 11, 16, 8)).stopped(at: local(2026, 11, 16, 5))
        let decision = NightlyCapture.decide(now: local(2026, 11, 16, 5, 30), settings: NightlyMotionSettings(), plan: plan,
                                             armedAt: local(2026, 11, 15, 22), conditions: ready, calendar: calendar)
        #expect(decision == .init(action: .none, wake: local(2026, 11, 16, 22)))
    }

    @Test func lastNightsRecordingDoesNotBlockTonight() {
        let lastNight = RecordingPlan(start: local(2026, 11, 14, 22), end: local(2026, 11, 15, 8))
        let decision = NightlyCapture.decide(now: local(2026, 11, 15, 22, 20), settings: NightlyMotionSettings(), plan: lastNight,
                                             armedAt: local(2026, 11, 14, 22), conditions: ready, calendar: calendar)
        #expect(decision.action == .arm(RecordingPlan(start: local(2026, 11, 15, 22, 20), end: local(2026, 11, 16, 8))))
    }

    @Test func lowPowerModeSkipsAndRetriesUntilItIsOff() {
        let now = local(2026, 11, 15, 22, 10)
        let lowPower = NightlyCapture.Conditions(lowPower: true)
        let skip = NightlyCapture.decide(now: now, settings: NightlyMotionSettings(), plan: nil, armedAt: nil,
                                         conditions: lowPower, calendar: calendar)
        #expect(skip == .init(action: .skip(.lowPower), wake: now.addingTimeInterval(30 * 60)))
        let later = now.addingTimeInterval(30 * 60)
        let armed = NightlyCapture.decide(now: later, settings: NightlyMotionSettings(), plan: nil, armedAt: nil,
                                          conditions: ready, calendar: calendar)
        #expect(armed.action == .arm(RecordingPlan(start: later, end: local(2026, 11, 16, 8))))
    }

    @Test func withoutPermissionItSkipsToTomorrow() {
        let decision = NightlyCapture.decide(now: local(2026, 11, 15, 23), settings: NightlyMotionSettings(), plan: nil,
                                             armedAt: nil, conditions: .init(canRecord: false), calendar: calendar)
        #expect(decision == .init(action: .skip(.notAuthorized), wake: local(2026, 11, 16, 22)))
    }

    @Test func turnedOffItNeitherArmsNorWakes() {
        let decision = NightlyCapture.decide(now: local(2026, 11, 15, 23), settings: NightlyMotionSettings(enabled: false),
                                             plan: nil, armedAt: nil, conditions: ready, calendar: calendar)
        #expect(decision == .init(action: .none, wake: nil))
    }

    /// Following each decision's wake from one afternoon, the Watch arms exactly one recording per night, each from
    /// the night's start to its end, with no manual start.
    @Test func sevenNightsInARowEachArmOnce() throws {
        var now = local(2026, 11, 15, 14)
        var plan: RecordingPlan?
        var armedAt: Date?
        var plans: [RecordingPlan] = []
        while now < local(2026, 11, 22, 14) {
            let decision = NightlyCapture.decide(now: now, settings: NightlyMotionSettings(), plan: plan, armedAt: armedAt,
                                                 conditions: ready, calendar: calendar)
            if case .arm(let next) = decision.action {
                plan = next
                armedAt = now
                plans.append(next)
            }
            let wake = try #require(decision.wake)
            #expect(wake > now)
            now = wake
        }
        #expect(plans.count == 7)
        for (index, plan) in plans.enumerated() {
            #expect(plan.start == local(2026, 11, 15 + index, 22))
            #expect(plan.end == local(2026, 11, 16 + index, 8))
            #expect(plan.duration <= RecordingPlan.maximumDuration)
        }
    }

    // MARK: Reading a night back

    @Test func spansEndOnUnixMultiplesAndWaitForTheRecorder() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_123.4)
        let progress = NightProgress(plan: RecordingPlan(start: start, end: start.addingTimeInterval(3600)))
        #expect(progress.nextSpan(now: start.addingTimeInterval(60)) == nil)
        let span = try #require(progress.nextSpan(now: start.addingTimeInterval(3 * 3600)))
        #expect(span.start == start)
        #expect(span.end.timeIntervalSince1970 == 1_800_000_600)
        #expect(span.end.timeIntervalSince1970.truncatingRemainder(dividingBy: NightlyCapture.span) == 0)
        // The recorder returns (from, to]; a reading exactly at the span's start is asked for too.
        #expect(NightProgress.query(for: span).start == start.addingTimeInterval(-1))
    }

    @Test func spanBySpanBinsEqualTheWholeNightAtOnce() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_001.3), end = start.addingTimeInterval(2 * 3600 + 17)
        // 10 Hz with movement every few minutes, and a reading exactly on a span boundary.
        var samples = stride(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970, by: 0.1).enumerated().map { index, t in
            MotionSample(time: t, x: index % 1700 < 30 ? 0.4 : 0, y: 0, z: index % 1700 < 30 ? 1.3 : 1)
        }
        samples.append(still(1_800_000_600))
        let whole = MotionSummarizer.file(samples: samples, from: start, to: end, timeZone: Self.zone, device: "Watch")

        var progress = NightProgress(plan: RecordingPlan(start: start, end: end))
        let later = end.addingTimeInterval(3600)
        var spans = 0
        while let span = progress.nextSpan(now: later) {
            let query = NightProgress.query(for: span)
            let returned = samples.filter { $0.time > query.start.timeIntervalSince1970 && $0.time <= query.end.timeIntervalSince1970 }
            let added = progress.add(returned, for: span, now: later)
            #expect(added)
            spans += 1
        }
        #expect(progress.isComplete)
        #expect(spans == 13)
        #expect(progress.file(timeZone: Self.zone, device: "Watch") == whole)
        #expect(try WatchMotionFile.decode(progress.file(timeZone: Self.zone, device: "Watch").encoded()).bins.count == whole.bins.count)
    }

    @Test func anEmptySpanIsReadAgainUntilItCannotFill() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var progress = NightProgress(plan: RecordingPlan(start: start, end: start.addingTimeInterval(3600)))
        let soon = start.addingTimeInterval(600 + NightlyCapture.settle)
        let span = try #require(progress.nextSpan(now: soon))
        let early = progress.add([], for: span, now: soon)
        #expect(!early)
        #expect(progress.cursor == start)
        let late = progress.add([], for: span, now: span.end.addingTimeInterval(NightlyCapture.emptyGrace))
        #expect(late)
        #expect(progress.cursor == span.end)
        #expect(progress.bins.count == 0)
    }

    @Test func aReadingHandedBackTwiceCountsOnce() {
        let bins = MotionSummarizer.summarize([still(10), still(10.02), still(10.02), still(10.04)])
        #expect(bins.samples == [3])
    }

    // MARK: Capture notes

    @Test func batteryCostUsesTheLastReadingOffTheChargerBeforeTheEnd() throws {
        let armed = local(2026, 11, 15, 22)
        let plan = RecordingPlan(start: armed, end: local(2026, 11, 16, 6))
        var capture = WatchMotionCapture(plan: plan, automatic: true, armedAt: armed,
                                         battery: .init(level: 0.84, charging: false, at: armed))
        capture.note(.init(level: 0.70, charging: false, at: local(2026, 11, 16, 3)), planEnd: plan.end)
        capture.note(.init(level: 0.64, charging: false, at: local(2026, 11, 16, 6, 5)), planEnd: plan.end)
        capture.note(.init(level: 0.60, charging: true, at: local(2026, 11, 16, 6, 7)), planEnd: plan.end)
        capture.note(.init(level: 0.50, charging: false, at: local(2026, 11, 16, 9)), planEnd: plan.end)
        #expect(capture.batteryEnd?.level == 0.64)
        let perHour = try #require(capture.batteryPerHour)
        #expect(abs(perHour - 0.20 / (8 + 5.0 / 60)) < 1e-9)
        #expect(capture.summary == "Nightly · battery 84% → 64% over 8.1 h")
        #expect(capture.recordedFromMs == Int64(armed.timeIntervalSince1970 * 1000))

        var charging = capture
        charging.batteryStart?.charging = true
        #expect(charging.batteryPerHour == nil)
        let unmeasured = WatchMotionCapture(plan: plan, automatic: false, armedAt: armed, battery: nil)
        #expect(unmeasured.summary == "Manual")
    }

    @Test func captureTravelsAsTransferMetadata() throws {
        let plan = RecordingPlan(start: Date(timeIntervalSince1970: 1_800_000_000), hours: 8)
        var capture = WatchMotionCapture(plan: plan, automatic: true, armedAt: plan.start,
                                         battery: .init(level: 0.9, charging: false, at: plan.start))
        capture.rearms = 1
        let metadata: [String: Any] = ["kind": "watch-motion", WatchMotionCapture.metadataKey: try #require(capture.metadata())]
        #expect(WatchMotionCapture.decode(metadata: metadata) == capture)
        #expect(WatchMotionCapture.decode(metadata: ["kind": "watch-motion"]) == nil)
        #expect(WatchMotionCapture.decode(metadata: nil) == nil)
        #expect(capture.summary == "Nightly · battery 90% at start · re-armed 1×")
    }

    @Test func settingsTakeLocalClockTimesAndRoundTripTheContext() throws {
        let settings = NightlyMotionSettings(enabled: true, bed: local(2026, 11, 14, 23, 40), wake: local(2026, 11, 15, 6, 55),
                                             calendar: calendar)
        #expect(settings.bedMinutes == 23 * 60 + 40)
        #expect(settings.wakeMinutes == 6 * 60 + 55)
        #expect(settings.fromHealth)
        #expect(NightlyMotionSettings.decode(context: try settings.context()) == settings)
        #expect(NightlyMotionSettings.decode(context: [:]) == nil)
        #expect(NightlyMotionSettings().enabled)
        #expect(!NightlyMotionSettings().fromHealth)
    }

    // MARK: iPhone

    @Test func inboxKeepsCaptureNotesBesideTheFilesNotInThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchMotionInbox(directory: root.appendingPathComponent("WatchMotion"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let from = Date(timeIntervalSince1970: 1_800_000_000)
        let file = MotionSummarizer.file(samples: [still(1_800_000_001)], from: from, to: from.addingTimeInterval(3600),
                                         timeZone: .gmt, device: "Watch")
        let incoming = root.appendingPathComponent("incoming.json")
        let data = try file.encoded()
        try data.write(to: incoming)
        let capture = WatchMotionCapture(plan: RecordingPlan(start: from, hours: 1), automatic: true, armedAt: from,
                                         battery: .init(level: 0.8, charging: false, at: from))

        let stored = try inbox.store(contentsOf: incoming, capture: capture)
        #expect(stored.capture == capture)
        #expect(try Data(contentsOf: stored.url) == data)
        #expect(inbox.recordings().map(\.capture) == [capture])
        let exported = try JSONSerialization.jsonObject(with: Data(contentsOf: inbox.combinedExport(in: root))) as? [[String: Any]]
        #expect(exported?.count == 1)
        #expect(exported?.first?[WatchMotionCapture.metadataKey] == nil)

        // A note for a different night is not filed against this one.
        let other = WatchMotionCapture(plan: RecordingPlan(start: from.addingTimeInterval(5), hours: 1), automatic: true,
                                       armedAt: from, battery: nil)
        let second = root.appendingPathComponent("second.json")
        try data.write(to: second)
        #expect(try inbox.store(contentsOf: second, capture: other).capture == capture)
    }

    @MainActor @Test func receiverTakesTheUsualNightFromHealthAndKeepsTheToggle() throws {
        let suite = "nightly-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let receiver = WatchMotionReceiver(inbox: WatchMotionInbox(directory: root), defaults: defaults)
        #expect(receiver.nightlyEnabled)
        #expect(receiver.nightly == NightlyMotionSettings())

        let bed = Date(timeIntervalSince1970: 1_800_000_000)
        receiver.updateNightly(bed: bed, wake: bed.addingTimeInterval(7.5 * 3600))
        #expect(receiver.nightly.fromHealth)
        let night = receiver.nightly
        receiver.updateNightly(bed: bed, wake: bed.addingTimeInterval(1.5 * 3600))  // a nap keeps the usual night
        receiver.updateNightly(bed: nil, wake: nil)
        #expect(receiver.nightly == night)

        receiver.nightlyEnabled = false
        let relaunched = WatchMotionReceiver(inbox: WatchMotionInbox(directory: root), defaults: defaults)
        #expect(!relaunched.nightlyEnabled)
        #expect(relaunched.nightly.bedMinutes == night.bedMinutes)
        relaunched.updateNightly(bed: bed, wake: bed.addingTimeInterval(8 * 3600))
        #expect(!relaunched.nightlyEnabled)
    }
}
