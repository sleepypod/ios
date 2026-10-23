import AVFoundation
import Foundation
import Testing
import UIKit
@testable import Sleepypod

@Suite("Snore event tracking")
struct SnoreEventTrackerTests {
    private func window(_ second: Double, _ confidence: Double) -> SnoreWindow {
        SnoreWindow(startMs: Int64(second * 1000), durationMs: 3_000, confidence: confidence)
    }

    @Test func opensAtTheOnThresholdAndClosesAfterTwoQuietWindows() {
        var tracker = SnoreEventTracker(captureId: "c", detectorVersion: "v")
        for (second, confidence) in [(0.0, 0.2), (1.5, 0.7), (3.0, 0.5), (4.5, 0.9), (6.0, 0.3), (7.5, 0.1), (9.0, 0.1)] {
            tracker.add(window(second, confidence))
        }
        #expect(tracker.events == [SnoreEvent(captureId: "c", startMs: 1_500, endMs: 7_500, confidence: 0.9, detectorVersion: "v")])
        #expect(!tracker.isOpen)
    }

    @Test func oneQuietWindowDoesNotSplitAnEvent() {
        var tracker = SnoreEventTracker(captureId: "c", detectorVersion: "v")
        for (second, confidence) in [(0.0, 0.8), (1.5, 0.2), (3.0, 0.7)] { tracker.add(window(second, confidence)) }
        tracker.finish()
        #expect(tracker.events.count == 1)
        #expect(tracker.events[0].endMs == 6_000)
    }

    @Test func closeEventsMergeAndDistantOnesStaySeparate() {
        var tracker = SnoreEventTracker(captureId: "c", detectorVersion: "v")
        for (second, confidence) in [(0.0, 0.8), (1.5, 0.1), (3.0, 0.1)] { tracker.add(window(second, confidence)) }
        tracker.add(window(5.0, 0.7)) // starts 2 s after the first event ended: merges
        tracker.finish()
        #expect(tracker.events.count == 1)
        #expect(tracker.events[0].startMs == 0)
        #expect(tracker.events[0].endMs == 8_000)
        tracker.add(window(30, 0.65))
        tracker.finish()
        #expect(tracker.events.count == 2)
        #expect(tracker.events[1].confidence == 0.65)
    }

    @Test func belowTheOnThresholdNothingOpens() {
        var tracker = SnoreEventTracker(captureId: "c", detectorVersion: "v")
        tracker.add(window(0, 0.59))
        tracker.finish()
        #expect(tracker.events.isEmpty)
    }
}

@Suite("Snore coverage, knocks and lifecycle")
struct SnoreCaptureLogicTests {
    @Test func coverageCountsClosedAndOpenSpans() {
        var coverage = CoverageTracker()
        coverage.end(at: 5) // ignored: nothing open
        coverage.begin(at: 1_000)
        coverage.begin(at: 1_500) // ignored: already open
        coverage.end(at: 4_000)
        coverage.begin(at: 6_000)
        coverage.end(at: 5_000) // ends before it began: dropped
        coverage.begin(at: 10_000)
        #expect(coverage.intervals == [TimeInterval64(startMs: 1_000, endMs: 4_000)])
        #expect(coverage.totalMs() == 3_000)
        #expect(coverage.totalMs(now: 12_000) == 5_000)
        #expect(coverage.totalMs(now: 9_000) == 3_000)
    }

    @Test func knockDetectorFindsSharpTransientsAboveTheFloorOnce() {
        var detector = KnockDetector()
        let rate = 1_000.0
        var samples = (0..<2_000).map { i in Float(0.01 * sin(Double(i) / 3)) }
        for start in [600, 700, 1_400] { for i in start..<(start + 5) { samples[i] = 0.9 } }
        let onsets = detector.process(samples, startMs: 10_000, sampleRate: rate)
        // 700 is inside the 150 ms refractory period after 600.
        #expect(onsets == [10_600, 11_400])
    }

    @Test func knockDetectorIgnoresQuietAudioAndTheWarmUp() {
        var detector = KnockDetector()
        var samples = [Float](repeating: 0.001, count: 1_000)
        samples[10] = 0.9 // before the floor has history
        samples[800] = 0.04 // loud relative to the floor but under the minimum peak
        #expect(detector.process(samples, startMs: 0, sampleRate: 1_000).isEmpty)
    }

    @Test func knockWindowKeepsOpeningAndClosingMinutes() {
        var window = KnockWindow(sessionStartMs: 0)
        for onset: Int64 in [1_000, 2_000, 61_000, 3_000_000, 3_100_000, 3_150_000] { window.add(onset) }
        #expect(window.knocks(endMs: 3_160_000) == [1_000, 2_000, 3_100_000, 3_150_000])
        #expect(window.knocks(endMs: 3_120_000) == [1_000, 2_000, 3_100_000])
    }

    @Test func machineTracksInterruptionsAndCoverage() {
        var machine = CaptureMachine()
        do { let ok = machine.interrupt("call", at: 1); #expect(!ok) }
        do { let ok = machine.resume(at: 1); #expect(!ok) }
        do { let ok = machine.stop(at: 1); #expect(!ok) }
        do { let ok = machine.start(at: 0); #expect(ok) }
        do { let ok = machine.start(at: 5); #expect(!ok) }
        do { let ok = machine.interrupt("call", at: 1_000); #expect(ok) }
        #expect(machine.state == .interrupted("call"))
        #expect(machine.isActive)
        do { let ok = machine.resume(at: 3_000); #expect(ok) }
        do { let ok = machine.stop(at: 5_000); #expect(ok) }
        #expect(machine.state == .stopped)
        #expect(machine.interruptions == [CaptureInterruption(startMs: 1_000, endMs: 3_000, reason: "call")])
        #expect(machine.coverage.intervals == [TimeInterval64(startMs: 0, endMs: 1_000), TimeInterval64(startMs: 3_000, endMs: 5_000)])
    }

    @Test func stoppingWhileInterruptedClosesTheGapAndFailureEndsCoverage() {
        var machine = CaptureMachine()
        machine.start(at: 0)
        machine.interrupt("route change", at: 2_000)
        machine.stop(at: 4_000)
        #expect(machine.interruptions.last?.endMs == 4_000)
        #expect(machine.coverage.totalMs() == 2_000)
        machine.start(at: 10_000)
        machine.fail("engine", at: 11_000)
        #expect(machine.state == .failed("engine"))
        #expect(machine.coverage.totalMs() == 1_000)
        #expect(!machine.isActive)
    }

    @Test func hostClockMapsHostSecondsToUnixMilliseconds() {
        let anchor = HostClockAnchor(unixMs: 1_000_000, hostSeconds: 50)
        #expect(anchor.unixMs(hostSeconds: 51.5) == 1_001_500)
        #expect(anchor.unixMs(hostSeconds: 49.9996) == 1_000_000)
    }

    @Test func documentEncodesTheTrainingContractFieldsAndNoAudio() throws {
        var document = SnoreSessionDocument(captureId: "abc", device: "iPhone", osVersion: "iOS 26.0", appVersion: "1.1.1",
                                            timeZone: "America/Los_Angeles", startMs: 1_000, detectorVersion: "v",
                                            classifier: .init(windowSeconds: 3, overlapFactor: 0.5, onThreshold: 0.6, offThreshold: 0.4))
        document.events = [SnoreEvent(captureId: "abc", startMs: 2_000, endMs: 62_000, confidence: 0.8, detectorVersion: "v"),
                           SnoreEvent(captureId: "abc", startMs: 70_000, endMs: 80_000, confidence: 0.7, detectorVersion: "v")]
        document.coverage = [TimeInterval64(startMs: 1_000, endMs: 3_601_000)]
        let data = try SnoreSessionDocument.encoder().encode(document)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? String == "sleepypod-snore-capture-v1")
        let event = try #require((json["events"] as? [[String: Any]])?.first)
        #expect(Set(event.keys) == ["captureId", "startMs", "endMs", "eventType", "confidence", "detectorVersion", "labelOrigin"])
        #expect(event["labelOrigin"] as? String == "predicted")
        #expect(!String(decoding: data, as: UTF8.self).lowercased().contains("audiodata"))
        #expect(try JSONDecoder().decode(SnoreSessionDocument.self, from: data) == document)
        #expect(document.snoreMs == 70_000)
        #expect(document.longestEventMs == 60_000)
        #expect(document.coveredMs == 3_600_000)
    }
}

// MARK: - Service

private final class FakeSource: SnoreAudioSource, @unchecked Sendable {
    var starts = 0, stops = 0
    var failNextStart: SnoreCaptureError?
    var onWindow: (@Sendable (SnoreWindow) -> Void)?
    var onKnock: (@Sendable (Int64) -> Void)?

    func start(onWindow: @escaping @Sendable (SnoreWindow) -> Void,
               onKnock: @escaping @Sendable (Int64) -> Void) throws -> SnoreAudioFormat {
        if let error = failNextStart { failNextStart = nil; throw error }
        starts += 1
        self.onWindow = onWindow
        self.onKnock = onKnock
        return SnoreAudioFormat(sampleRate: 48_000, channelCount: 1, windowSeconds: 2.97, overlapFactor: 0.5)
    }

    func stop() { stops += 1 }
}

private struct FakePermission: MicrophonePermission {
    var isGranted: Bool
    var isDenied = false
    var answer = true
    func request() async -> Bool { answer }
}

private final class FakeClock: @unchecked Sendable {
    var now: Int64 = 1_000_000
}

@Suite("Snore capture service")
@MainActor
struct SnoreCaptureServiceTests {
    private func make(permission: FakePermission = FakePermission(isGranted: true)) -> (SnoreCaptureService, FakeSource, FakeClock, URL, NotificationCenter) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("snore-\(UUID().uuidString)")
        let source = FakeSource(), clock = FakeClock(), center = NotificationCenter()
        let service = SnoreCaptureService(directory: dir, source: source, permission: permission,
                                          clock: { clock.now }, notifications: center)
        return (service, source, clock, dir, center)
    }

    @Test func aNightRecordsEventsKnocksCoverageAndSavesTheSession() async throws {
        let (service, source, clock, dir, _) = make()
        await service.start()
        #expect(service.status == .recording)
        #expect(service.current?.sampleRate == 48_000)
        #expect(service.current?.classifier.windowSeconds == 2.97)
        service.handleKnock(1_010_000)
        for (offset, confidence) in [(0, 0.9), (1_500, 0.8), (3_000, 0.1), (4_500, 0.1)] {
            service.handle(SnoreWindow(startMs: 1_100_000 + Int64(offset), durationMs: 3_000, confidence: confidence))
        }
        #expect(service.current?.events.count == 1)
        clock.now = 1_000_000 + 3_600_000
        service.handleKnock(clock.now - 5_000)
        service.stop()
        #expect(source.stops == 1)
        #expect(service.status == .idle)
        let saved = try #require(SnoreCaptureService.sessions(in: dir).first)
        #expect(saved.endMs == 4_600_000)
        #expect(saved.stopReason == "user")
        #expect(saved.events.count == 1)
        #expect(saved.knocks == [1_010_000, 4_595_000])
        #expect(saved.coveredMs == 3_600_000)
        #expect(service.lastSession == saved)
        service.stop() // already stopped: no-op
        #expect(source.stops == 1)
    }

    @Test func interruptionsPauseListeningAndResume() async {
        let (service, source, clock, _, _) = make()
        await service.start()
        clock.now += 60_000
        service.interrupt("audio interruption")
        #expect(service.status == .interrupted("audio interruption"))
        service.handle(SnoreWindow(startMs: clock.now, durationMs: 3_000, confidence: 0.9)) // ignored while paused
        clock.now += 30_000
        service.resume()
        #expect(service.status == .recording)
        #expect(source.starts == 2)
        clock.now += 10_000
        service.routeChanged()
        #expect(source.starts == 3)
        #expect(service.status == .recording)
        clock.now += 10_000
        service.stop()
        let last = service.lastSession
        #expect(last?.events.isEmpty == true)
        #expect(last?.interruptions.map(\.reason) == ["audio interruption", "route change"])
        #expect(last?.coveredMs == Int64(60_000 + 10_000 + 10_000))
    }

    @Test func interruptionNotificationsMapToPauseAndResume() {
        typealias S = SnoreCaptureService
        let began = AVAudioSession.InterruptionType.began.rawValue, ended = AVAudioSession.InterruptionType.ended.rawValue
        #expect(S.interruptionAction([AVAudioSessionInterruptionTypeKey: began]) == .pause)
        #expect(S.interruptionAction([AVAudioSessionInterruptionTypeKey: ended]) == .resume)
        #expect(S.interruptionAction([AVAudioSessionInterruptionTypeKey: ended,
                                      AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue]) == .resume)
        #expect(S.interruptionAction([AVAudioSessionInterruptionTypeKey: ended, AVAudioSessionInterruptionOptionKey: UInt(0)]) == .none)
        #expect(S.interruptionAction(nil) == .none)
        #expect(S.interruptionAction([AVAudioSessionInterruptionTypeKey: UInt(99)]) == .none)
    }

    @Test func notificationsReachTheService() async {
        let (service, _, _, dir, center) = make()
        await service.start()
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        center.post(name: AVAudioSession.routeChangeNotification, object: nil)
        center.post(name: UIApplication.willTerminateNotification, object: nil)
        for _ in 0..<50 where service.isActive { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(!service.isActive)
        #expect(SnoreCaptureService.sessions(in: dir).first?.stopReason == "app terminated")
    }

    @Test func terminationSavesWhatExists() async {
        let (service, _, _, dir, _) = make()
        await service.start()
        service.terminate()
        #expect(SnoreCaptureService.sessions(in: dir).first?.stopReason == "app terminated")
    }

    @Test func aFailedRestartEndsTheSession() async {
        let (service, source, _, _, _) = make()
        await service.start()
        service.interrupt("call")
        source.failNextStart = .noInput
        service.resume()
        #expect(service.status == .failed(SnoreCaptureError.noInput.localizedDescription))
        #expect(service.lastSession?.stopReason?.hasPrefix("failed") == true)
        #expect(!service.isActive)
    }

    @Test func deniedOrRefusedMicrophoneNeverStarts() async {
        let (denied, deniedSource, _, _, _) = make(permission: FakePermission(isGranted: false, isDenied: true))
        await denied.start()
        #expect(denied.microphoneDenied)
        #expect(deniedSource.starts == 0)
        let (refused, refusedSource, _, _, _) = make(permission: FakePermission(isGranted: false, answer: false))
        await refused.start()
        #expect(refused.microphoneDenied)
        #expect(refusedSource.starts == 0)
        let (asked, askedSource, _, _, _) = make(permission: FakePermission(isGranted: false, answer: true))
        await asked.start()
        #expect(!asked.microphoneDenied)
        #expect(askedSource.starts == 1)
    }

    @Test func aSourceThatCannotStartReportsWhy() async {
        let (service, source, _, _, _) = make()
        source.failNextStart = .snoringUnavailable
        await service.start()
        #expect(service.status == .failed(SnoreCaptureError.snoringUnavailable.localizedDescription))
        #expect(!service.isActive)
        #expect(SnoreCaptureError.engine("x").localizedDescription.contains("x"))
    }

    @Test func sessionsCanBeDeleted() async {
        let (service, _, _, dir, _) = make()
        await service.start()
        service.stop()
        guard let saved = service.lastSession else { Issue.record("no session saved"); return }
        service.delete(saved)
        #expect(SnoreCaptureService.sessions(in: dir).isEmpty)
        #expect(service.lastSession == nil)
    }

    @Test func durationsReadAsMinutesOrHours() {
        #expect(SnoreCaptureView.duration(59_000) == "0 min")
        #expect(SnoreCaptureView.duration(25 * 60_000) == "25 min")
        #expect(SnoreCaptureView.duration(125 * 60_000) == "2 h 5 min")
    }
}
