import Foundation
import HealthKit
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

/// Health store holding what one Apple Watch recorded, or failing every read.
@MainActor
private final class WatchHealthStore: HealthSyncStore {
    var available = true
    var failReads = false
    var sleep: [HKCategorySample] = []
    var quantities: [HKQuantityTypeIdentifier: [HKQuantitySample]] = [:]
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { .sharingAuthorized }
    func authorize(write: Set<HKSampleType>, read: Set<HKObjectType>) async throws {}
    func save(_ samples: [HKSample]) async throws {}
    func delete(types: Set<HKSampleType>, deviceID: String, start: Date, end: Date, olderThan version: Int?) async throws {}
    func deleteAll(types: Set<HKSampleType>, olderThan version: Int) async throws {}
    func sleepSamples(start: Date, end: Date) async throws -> [HKCategorySample] {
        if failReads { throw URLError(.cannotOpenFile) }
        return sleep
    }
    func quantitySamples(_ type: HKQuantityTypeIdentifier, start: Date, end: Date) async throws -> [HKQuantitySample] {
        if failReads { throw URLError(.cannotOpenFile) }
        return quantities[type] ?? []
    }
}

@Suite("Sending Watch data to the pod")
@MainActor
struct PodWatchSendTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let watch = HKDevice(name: "Apple Watch", manufacturer: "Apple", model: "Watch", hardwareVersion: "Watch6,1",
                                 firmwareVersion: nil, softwareVersion: nil, localIdentifier: nil, udiDeviceIdentifier: nil)

    private func service(_ store: WatchHealthStore) -> HealthSyncService {
        let service = HealthSyncService(store: store, defaults: UserDefaults(suiteName: "pod-upload-\(UUID().uuidString)")!)
        service.enabled = true
        return service
    }

    private func watchNight(_ store: WatchHealthStore) {
        let start = now.addingTimeInterval(-8 * 3600)
        store.sleep = [HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                        start: start, end: start.addingTimeInterval(3600), device: watch, metadata: nil)]
        func quantity(_ type: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double) -> HKQuantitySample {
            HKQuantitySample(type: HKQuantityType(type), quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: start, end: start, device: watch, metadata: nil)
        }
        store.quantities = [.heartRate: [quantity(.heartRate, .count().unitDivided(by: .minute()), 55)],
                            .respiratoryRate: [quantity(.respiratoryRate, .count().unitDivided(by: .minute()), 15)],
                            .heartRateVariabilitySDNN: [quantity(.heartRateVariabilitySDNN, .secondUnit(with: .milli), 40)]]
    }

    @Test func aFailedHealthReadSendsNothing() async {
        let store = WatchHealthStore()
        store.failReads = true
        let api = MockAPIClient()
        let health = service(store)
        #expect(await health.sendWatchData(api: api, side: .left, days: 2, now: now) == nil)
        #expect(api.importCalls == 0)
        #expect(health.lastPodUpload == nil)
        #expect(health.podUploadError != nil)
    }

    @Test func aBoundaryConflictSkipsOnlyThatNight() async {
        let store = WatchHealthStore()
        watchNight(store)
        let api = MockAPIClient()
        api.importStages = { _, _ in throw APIError.serverError(message: "Segments overlap stored reference stages: 1 conflict") }
        let health = service(store)
        let report = await health.sendWatchData(api: api, side: .left, days: 2, now: now)
        #expect(report?.rejectedNights == 1)
        #expect(report?.heartRate == 1)
        #expect(report?.hrv == 1)
        #expect(health.podUploadError == nil)
    }

    @Test func otherServerErrorsSurfaceAndKeepWhatWasStored() async {
        let store = WatchHealthStore()
        watchNight(store)
        let api = MockAPIClient()
        api.importSamples = { _, _, _ in throw APIError.serverError(message: "Failed to import reference samples: disk full") }
        let health = service(store)
        let report = await health.sendWatchData(api: api, side: .left, days: 2, now: now)
        #expect(report?.stages == 1)
        #expect(report?.heartRate == 1)
        #expect(report?.breathing == 0)
        #expect(report?.rejectedNights == 0)
        #expect(health.podUploadError != nil)
        #expect(health.lastPodUpload?.report == report)
    }
}
