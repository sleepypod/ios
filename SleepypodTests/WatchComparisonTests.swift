import Testing
import Foundation
import HealthKit
@testable import Sleepypod

@Suite("Apple Watch comparison")
@MainActor
struct WatchComparisonTests {
    private func epoch(_ minute: Int, _ stage: SleepAnalyzer.SleepStage) -> SleepAnalyzer.SleepEpoch {
        SleepAnalyzer.SleepEpoch(start: Date(timeIntervalSince1970: Double(minute) * 60), duration: 60,
                                 stage: stage, heartRate: 60, hrv: nil, breathingRate: nil)
    }
    private func watch(_ from: Int, _ to: Int, _ stage: SleepAnalyzer.SleepStage) -> WatchComparison.StageSample {
        WatchComparison.StageSample(start: Date(timeIntervalSince1970: Double(from) * 60),
                                    end: Date(timeIntervalSince1970: Double(to) * 60), stage: stage)
    }

    @Test func agreementCountsOnlyMinutesTheWatchStaged() {
        let epochs = [epoch(0, .light), epoch(1, .light), epoch(2, .deep), epoch(3, .deep), epoch(4, .rem), epoch(10, .wake)]
        let samples = [watch(0, 2, .light), watch(2, 3, .light), watch(3, 4, .deep), watch(4, 5, .rem)]
        let result = WatchComparison.stageAgreement(epochs: epochs, watch: samples)
        #expect(result.comparedSeconds == 300)
        #expect(result.matchedSeconds == 240)
        #expect(result.percent == 80)
        #expect(result.disagreements == [WatchComparison.Disagreement(ours: .deep, watch: .light, seconds: 60)])
    }

    @Test func adjacentWatchSamplesMergeForDrawing() {
        let merged = WatchComparison.merged([watch(0, 1, .light), watch(1, 2, .light), watch(2, 3, .deep), watch(20, 21, .deep)])
        #expect(merged == [watch(0, 2, .light), watch(2, 3, .deep), watch(20, 21, .deep)])
    }

    @Test func overlappingWatchStagesAreSkipped() {
        let result = WatchComparison.stageAgreement(epochs: [epoch(0, .light)], watch: [watch(0, 1, .light), watch(0, 1, .deep)])
        #expect(result.comparedSeconds == 0)
        #expect(result.percent == nil)
    }

    @Test func heartRatePairsNearestPodReadingWithinTolerance() {
        let vitals = [0, 60, 120, 600].map { VitalsRecord(id: $0, heartRate: 50 + Double($0) / 60, date: Date(timeIntervalSince1970: Double($0))) }
        let watch = [WatchComparison.Reading(date: Date(timeIntervalSince1970: 70), value: 52),
                     WatchComparison.Reading(date: Date(timeIntervalSince1970: 400), value: 70)]
        let pairs = WatchComparison.heartRatePairs(vitals: vitals, watch: watch, tolerance: 90)
        #expect(pairs.count == 1)
        #expect(pairs[0].ours == 51)
        #expect(pairs[0].watch == 52)
        let comparison = WatchComparison.build(epochs: [], vitals: vitals, watchStages: [], watchHeartRate: watch, watchHRV: [], watchBreathing: [])
        #expect(comparison.heartRateError == 1)
        #expect(comparison.heartRateBias == -1)
        #expect(comparison.hasWatchData)
    }

    @Test func nightAveragesIgnoreMissingValues() {
        let vitals = [VitalsRecord(id: 1, hrv: 40, breathingRate: 14), VitalsRecord(id: 2, hrv: 60), VitalsRecord(id: 3)]
        let comparison = WatchComparison.build(epochs: [], vitals: vitals, watchStages: [], watchHeartRate: [],
                                               watchHRV: [.init(date: Date(), value: 55)], watchBreathing: [])
        #expect(comparison.hrv.ours == 50)
        #expect(comparison.hrv.watch == 55)
        #expect(comparison.hrv.difference == -5)
        #expect(comparison.breathing.ours == 14)
        #expect(comparison.breathing.watch == nil)
        let empty = WatchComparison.build(epochs: [], vitals: [], watchStages: [], watchHeartRate: [], watchHRV: [], watchBreathing: [])
        #expect(!empty.hasWatchData)
    }

    @Test func healthStagesMapBothWaysAndOwnWritesAreNotWatchData() throws {
        for stage: SleepAnalyzer.SleepStage in [.wake, .rem, .light, .deep] {
            #expect(HealthSyncService.stage(for: HealthSyncService.stageValue(stage)) == stage)
        }
        #expect(HealthSyncService.stage(for: HKCategoryValueSleepAnalysis.inBed.rawValue) == nil)
        let sample = HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                      start: Date(), end: Date().addingTimeInterval(60))
        #expect(!HealthSyncService.isWatch(sample))
        #expect(HealthSyncService.watchStages([sample]).isEmpty)
    }

    @Test func demoIsDeterministicAndDisagreesSomewhere() throws {
        let json = """
        {"id":7,"side":"left","enteredBedAt":0,"leftBedAt":28800,"sleepDurationSeconds":27000}
        """
        let record = try JSONDecoder().decode(SleepRecord.self, from: Data(json.utf8))
        let stages: [SleepAnalyzer.SleepStage] = [.wake, .light, .deep, .light, .rem]
        let epochs = (0..<240).map { epoch($0, stages[$0 / 48]) }
        let vitals = (0..<96).map { VitalsRecord(id: $0, heartRate: 55 + Double($0 % 7), hrv: 40 + Double($0 % 5), breathingRate: 14,
                                                 date: Date(timeIntervalSince1970: Double($0) * 300)) }
        let a = WatchComparison.demo(record: record, epochs: epochs, vitals: vitals)
        let b = WatchComparison.demo(record: record, epochs: epochs, vitals: vitals)
        #expect(a.watchStages == b.watchStages)
        #expect(a.hasWatchData)
        let percent = try #require(a.stages.percent)
        #expect(percent > 60 && percent < 100)
        #expect(!a.stages.disagreements.isEmpty)
        #expect(!a.heartRate.isEmpty)
        #expect(a.hrv.watch != nil && a.breathing.watch != nil)
    }
}
