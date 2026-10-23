import Testing
import Foundation
@testable import Sleepypod

/// The Watch's overnight movement summary: bins, jerk, the file format sleepypod/training reads, and the
/// iPhone inbox that stores what the Watch sends.
@Suite("Watch movement")
struct WatchMotionTests {
    private func still(_ t: Double) -> MotionSample { MotionSample(time: t, x: 0, y: 0, z: 1) }

    @Test func binsAlignToUnixTimeAndOmitEmptySpans() {
        let samples = [still(100.1), still(100.5), still(101.9), still(106.2)]
        let bins = MotionSummarizer.summarize(samples, binSeconds: 2)
        #expect(bins.startMs == [100_000, 106_000])
        #expect(bins.samples == [3, 1])
        #expect(bins.meanMagnitude == [1, 1])
        #expect(bins.magnitudeVariance == [0, 0])
        #expect(bins.maxJerk == [0, 0])
        #expect(bins.movingSamples == [0, 0])
    }

    @Test func jerkCountsFastChangesOnlyBetweenCloseReadings() {
        let samples = [
            still(10.00),
            MotionSample(time: 10.02, x: 0, y: 0, z: 1.1),  // +0.1 g in 20 ms: 5 g/s
            MotionSample(time: 10.04, x: 0, y: 0, z: 1.101), // 0.05 g/s
            MotionSample(time: 11.00, x: 0, y: 0, z: 2.0),   // 0.96 s gap: not a jerk
        ]
        let bins = MotionSummarizer.summarize(samples.reversed(), binSeconds: 2, jerkThreshold: 1, maxGap: 0.5)
        #expect(bins.count == 1)
        #expect(abs(bins.maxJerk[0] - 5) < 1e-6)
        #expect(bins.movingSamples == [1])
        let mean = (1 + 1.1 + 1.101 + 2.0) / 4
        #expect(abs(bins.meanMagnitude[0] - mean) < 1e-9)
        #expect(bins.magnitudeVariance[0] > 0)
    }

    @Test func fileCarriesProvenanceAndOptionalRaw() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let from = Date(timeIntervalSince1970: 1_800_000_000), to = from.addingTimeInterval(4)
        let samples = [still(1_800_000_000.5), MotionSample(time: 1_800_000_002.25, x: 0.6, y: 0, z: 0.8)]
        let file = MotionSummarizer.file(samples: samples, from: from, to: to, timeZone: zone, device: "Watch")
        #expect(file.version == "watch-motion-v1")
        #expect(file.recordedFromMs == 1_800_000_000_000)
        #expect(file.recordedToMs == 1_800_000_004_000)
        #expect(file.timeZone == "America/Los_Angeles")
        #expect(file.utcOffsetSeconds == zone.secondsFromGMT(for: from))
        #expect(file.bins.count == 2)
        #expect(file.raw == nil)
        #expect(file.fileName == "watch-motion-1800000000000.json")
        let raw = MotionSummarizer.file(samples: samples, from: from, to: to, timeZone: zone, device: "Watch", includeRaw: true)
        #expect(raw.raw?.first == [1_800_000_000_500, 0, 0, 1])
    }

    @Test func encodingRoundTripsAndRejectsBadFiles() throws {
        let file = MotionSummarizer.file(samples: [still(5), still(7)], from: Date(timeIntervalSince1970: 4),
                                         to: Date(timeIntervalSince1970: 8), timeZone: .gmt, device: "Watch")
        #expect(try WatchMotionFile.decode(file.encoded()) == file)

        var wrongVersion = file
        wrongVersion.version = "watch-motion-v0"
        #expect(throws: WatchMotionFile.FormatError.unsupportedVersion("watch-motion-v0")) { try WatchMotionFile.decode(wrongVersion.encoded()) }
        var ragged = file
        ragged.bins.maxJerk.removeLast()
        #expect(throws: WatchMotionFile.FormatError.mismatchedColumns) { try WatchMotionFile.decode(ragged.encoded()) }
        var backwards = file
        backwards.recordedToMs = backwards.recordedFromMs - 1
        #expect(throws: WatchMotionFile.FormatError.badInterval) { try WatchMotionFile.decode(backwards.encoded()) }
        #expect(throws: (any Error).self) { try WatchMotionFile.decode(Data("{}".utf8)) }
    }

    @Test func recordingPlanClampsAndReadsBackOnlyWhatHasPassed() {
        let start = Date(timeIntervalSince1970: 1000)
        #expect(RecordingPlan(start: start, hours: 20).duration == 12 * 3600)
        #expect(RecordingPlan(start: start, hours: 0).duration == 1800)
        let plan = RecordingPlan(start: start, hours: 8)
        #expect(plan.end == start.addingTimeInterval(8 * 3600))
        #expect(plan.readableInterval(now: start) == nil)
        #expect(plan.readableInterval(now: start.addingTimeInterval(60))?.duration == 60)
        #expect(plan.readableInterval(now: start.addingTimeInterval(9 * 3600))?.end == plan.end)
    }

    @Test func inboxStoresValidFilesNewestFirstAndSkipsBadOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchMotionInbox(directory: root.appendingPathComponent("WatchMotion"))
        #expect(inbox.recordings().isEmpty)

        func incoming(_ startSeconds: Double) throws -> URL {
            let file = MotionSummarizer.file(samples: [still(startSeconds + 1)], from: Date(timeIntervalSince1970: startSeconds),
                                             to: Date(timeIntervalSince1970: startSeconds + 3600), timeZone: .gmt, device: "Watch")
            let url = root.appendingPathComponent(UUID().uuidString + ".json")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try file.encoded().write(to: url)
            return url
        }
        let older = try inbox.store(contentsOf: incoming(1000))
        _ = try inbox.store(contentsOf: incoming(9000))
        _ = try inbox.store(contentsOf: incoming(1000))  // a repeat delivery replaces the copy
        #expect(older.bins == 1)
        #expect(older.url.lastPathComponent == "watch-motion-1000000.json")
        try Data("not json".utf8).write(to: inbox.directory.appendingPathComponent("broken.json"))
        try Data("x".utf8).write(to: inbox.directory.appendingPathComponent("notes.txt"))
        let listed = inbox.recordings()
        #expect(listed.map(\.from.timeIntervalSince1970) == [9000, 1000])

        let bad = root.appendingPathComponent("bad.json")
        try Data("{}".utf8).write(to: bad)
        #expect(throws: (any Error).self) { try inbox.store(contentsOf: bad) }
    }

    @MainActor @Test func receiverListsTheInboxAtLaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchMotionInbox(directory: root)
        let file = MotionSummarizer.file(samples: [still(1)], from: Date(timeIntervalSince1970: 0),
                                         to: Date(timeIntervalSince1970: 2), timeZone: .gmt, device: "Watch")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try file.encoded().write(to: root.appendingPathComponent(file.fileName))
        let receiver = WatchMotionReceiver(inbox: inbox)
        #expect(receiver.recordings.count == 1)
        #expect(receiver.lastError == nil)
        #expect(WatchMotionInbox.standard.directory.lastPathComponent == "WatchMotion")

        receiver.received(.failure(WatchMotionFile.FormatError.badInterval))
        #expect(receiver.lastError?.hasPrefix("A Watch recording could not be read") == true)
        try FileManager.default.removeItem(at: root.appendingPathComponent(file.fileName))
        receiver.received(.success(WatchMotionInbox.Recording(url: root, from: .now, to: .now, bins: 0)))
        #expect(receiver.lastError == nil)
        #expect(receiver.recordings.isEmpty)
        receiver.activate()
    }
}
