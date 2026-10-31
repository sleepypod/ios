import Foundation
import Testing
@testable import Sleepypod

struct PodWatchUploadTests {
    private func sample(_ start: Double, _ end: Double, _ stage: SleepAnalyzer.SleepStage) -> WatchComparison.StageSample {
        WatchComparison.StageSample(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end), stage: stage)
    }

    @Test func overlapsResolveToTheLaterStartAndRunsMerge() {
        let base = 1_800_000_000.0
        let segments = PodWatchUpload.segments([
            sample(base, base + 600, .light),
            sample(base + 300, base + 900, .deep),
            sample(base + 900, base + 1200, .deep),
        ])
        #expect(segments == [
            PodWatchUpload.Segment(start: 1_800_000_000, end: 1_800_000_300, stage: .light),
            PodWatchUpload.Segment(start: 1_800_000_300, end: 1_800_001_200, stage: .deep),
        ])
    }

    @Test func fractionalSecondsFloorLikeAnExport() {
        let segments = PodWatchUpload.segments([sample(1_800_000_000.7, 1_800_000_060.9, .rem)])
        #expect(segments == [PodWatchUpload.Segment(start: 1_800_000_000, end: 1_800_000_060, stage: .rem)])
    }

    @Test func nightsSplitOnLongGaps() {
        let a = PodWatchUpload.Segment(start: 1_800_000_000, end: 1_800_003_600, stage: .light)
        let b = PodWatchUpload.Segment(start: 1_800_007_200, end: 1_800_010_800, stage: .deep)
        let c = PodWatchUpload.Segment(start: 1_800_086_400, end: 1_800_090_000, stage: .light)
        #expect(PodWatchUpload.nights([a, b, c]) == [[a, b], [c]])
    }

    @Test func samplesOutsideThePodRangeAreDropped() {
        let readings = [WatchComparison.Reading(date: Date(timeIntervalSince1970: 1_800_000_000), value: 2),
                        WatchComparison.Reading(date: Date(timeIntervalSince1970: 1_800_000_060), value: 14)]
        #expect(PodWatchUpload.samples(readings, in: PodWatchUpload.Metric.breathingRate.range)
                == [PodWatchUpload.Sample(timestamp: 1_800_000_060, value: 14)])
    }

    @Test func chunksCapAtTheBatchSize() {
        #expect(PodWatchUpload.chunks(Array(0..<4500)).map(\.count) == [2000, 2000, 500])
    }

    @Test func podMinutesPairWithTheWatchBinsBeforeThem() {
        let startMs: Int64 = 1_800_000_000_000
        var bins = WatchMotionFile.Bins()
        for index in 0..<60 {
            bins.startMs.append(startMs + Int64(index) * 2000)
            bins.samples.append(100)
            bins.meanMagnitude.append(1)
            bins.magnitudeVariance.append(0)
            bins.maxJerk.append(0)
            bins.movingSamples.append(index < 30 ? 1 : 3)
        }
        let file = WatchMotionFile(recordedFromMs: startMs, recordedToMs: startMs + 120_000, timeZone: "UTC", utcOffsetSeconds: 0,
                                   sampleRateHz: 50, binSeconds: 2, jerkThresholdGPerSecond: 1, device: "test", bins: bins)
        let pod = [MovementRecord(id: 1, totalMovement: 5, date: Date(timeIntervalSince1970: 1_800_000_060)),
                   MovementRecord(id: 2, totalMovement: 9, date: Date(timeIntervalSince1970: 1_800_000_120))]
        let comparison = WatchMotionComparison.build(file: file, pod: pod)
        #expect(comparison.pairs.map(\.watch) == [30, 90])
        #expect(comparison.pairs.map(\.pod) == [5, 9])
        #expect(comparison.watch.map(\.value) == [30, 90])
    }

    @Test func correlationNeedsEnoughVaryingMinutes() {
        #expect(WatchMotionComparison.pearson((0..<5).map { (Double($0), Double($0)) }) == nil)
        let pairs = (0..<20).map { (pod: Double($0), watch: Double($0) * 2 + 1) }
        #expect(abs((WatchMotionComparison.pearson(pairs) ?? 0) - 1) < 1e-9)
    }
}
