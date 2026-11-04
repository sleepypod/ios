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

    @MainActor @Test func summaryCallsAResendThatAddsNothingUpToDate() {
        var report = PodWatchUpload.Report(matchedStages: 513, matchedHeartRate: 5214, matchedBreathing: 927, matchedHRV: 96)
        #expect(HealthAccessView.podUploadSummary(report) == "Up to date")
        report.heartRate = 12
        #expect(HealthAccessView.podUploadSummary(report) == "Added 12 new readings")
        #expect(HealthAccessView.podUploadSummary(PodWatchUpload.Report()) == "No Apple Watch data found")
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
        #expect(comparison.span == Date(timeIntervalSince1970: 1_800_000_000)...Date(timeIntervalSince1970: 1_800_000_180))
    }

    @Test func watchLineBreaksAcrossGapsLongerThanTwoMinutes() {
        let points = [0, 60, 180, 600, 660].map { WatchMotionComparison.Point(date: Date(timeIntervalSince1970: $0), value: 1) }
        let runs = WatchMotionComparison.runs(points.reversed())
        #expect(runs.map { $0.map(\.date.timeIntervalSince1970) } == [[0, 60, 180], [600, 660]])
        #expect(WatchMotionComparison.runs([]).isEmpty)
    }

    @Test func onlyTheSpanBothSensorsCoverIsKept() {
        // The Watch covers minutes 10..<20; the pod reports minutes ending at 1...40.
        let base: Int64 = 1_800_000_000_000
        var bins = WatchMotionFile.Bins()
        for minute in 10..<20 {
            bins.startMs.append(base + Int64(minute) * 60_000)
            bins.samples.append(100)
            bins.meanMagnitude.append(1)
            bins.magnitudeVariance.append(0)
            bins.maxJerk.append(0)
            bins.movingSamples.append(1)
        }
        let file = WatchMotionFile(recordedFromMs: base, recordedToMs: base + 40 * 60_000, timeZone: "UTC", utcOffsetSeconds: 0,
                                   sampleRateHz: 50, binSeconds: 2, jerkThresholdGPerSecond: 1, device: "test", bins: bins)
        let pod = (1...40).map { MovementRecord(id: $0, totalMovement: $0, date: Date(timeIntervalSince1970: 1_800_000_000 + Double($0) * 60)) }
        let comparison = WatchMotionComparison.build(file: file, pod: pod)
        #expect(comparison.pod.map(\.value) == (11...20).map(Double.init))
        #expect(comparison.watch.count == 10)
        #expect(comparison.pairs.count == 10)

        // A pod that starts late trims the Watch's early minutes instead.
        let late = WatchMotionComparison.build(file: file, pod: Array(pod[14...]))
        #expect(late.watch.map(\.date.timeIntervalSince1970) == (14..<20).map { 1_800_000_000 + Double($0) * 60 })

        // Nothing to line up against: the Watch is left whole.
        #expect(WatchMotionComparison.build(file: file, pod: []).watch.count == 10)
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
    func deleteAll(types: Set<HKSampleType>, olderThan version: Int, since start: Date) async throws {}
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

@Suite("Sending Watch movement to the pod")
struct WatchMotionPodUploadTests {
    private func recording(raw: Bool) throws -> URL {
        let samples = [MotionSample(time: 5, x: 0, y: 0, z: 1), MotionSample(time: 7.5, x: 0.6, y: 0, z: 0.8)]
        let file = MotionSummarizer.file(samples: samples, from: Date(timeIntervalSince1970: 4), to: Date(timeIntervalSince1970: 10),
                                         timeZone: .gmt, device: "Watch", includeRaw: raw)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-motion-\(UUID().uuidString).json")
        try file.encoded().write(to: url)
        return url
    }

    @Test func endpointPostsToTheBiometricsRouteForOneSide() {
        let endpoint = APIEndpoint.watchMotion(side: .right)
        #expect(endpoint.path == "/api/biometrics/watch-motion")
        #expect(endpoint.method == .POST)
        #expect(endpoint.queryItems == [URLQueryItem(name: "side", value: "right")])
    }

    @Test func fileGoesAsRecordedButNeverWithRaw() async throws {
        let plain = try recording(raw: false), withRaw = try recording(raw: true)
        defer { try? FileManager.default.removeItem(at: plain); try? FileManager.default.removeItem(at: withRaw) }
        let api = MockAPIClient()

        let receipt = try api.uploadMotion(.right, Data())
        #expect(await WatchMotionPodUpload.send(contentsOf: plain, side: .right, api: api) == .stored(receipt))
        #expect(api.uploadMotionCalls.first?.0 == .right)
        #expect(api.uploadMotionCalls.first?.1 == (try Data(contentsOf: plain)))

        _ = await WatchMotionPodUpload.send(contentsOf: withRaw, side: .left, api: api)
        let sent = try WatchMotionFile.decode(try #require(api.uploadMotionCalls.last?.1))
        let original = try WatchMotionFile.decode(Data(contentsOf: withRaw))
        #expect(original.raw != nil)
        #expect(sent.raw == nil)
        #expect(sent.bins == original.bins)
        #expect(sent.version == "watch-motion-v2")
    }

    @Test func oldPodsReadAsUnsupportedAndFailuresKeepTheirReason() async throws {
        let url = try recording(raw: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = MockAPIClient()

        api.uploadMotion = { _, _ in throw APIError.notSupported("Watch movement upload") }
        #expect(await WatchMotionPodUpload.send(contentsOf: url, side: .left, api: api) == .unsupported)
        api.uploadMotion = { _, _ in throw URLError(.unsupportedURL) }
        #expect(await WatchMotionPodUpload.send(contentsOf: url, side: .left, api: api) == .unsupported)
        api.uploadMotion = { _, _ in throw APIError.serverError(message: "disk full") }
        #expect(await WatchMotionPodUpload.send(contentsOf: url, side: .left, api: api) == .failed("Server error: disk full"))

        let calls = api.uploadMotionCalls.count
        #expect(await WatchMotionPodUpload.send(contentsOf: url, side: .left, api: api, maxBytes: 10)
                == .failed("The recording is too large for the pod"))
        let missing = url.deletingLastPathComponent().appendingPathComponent("missing-\(UUID().uuidString).json")
        if case .failed(let message) = await WatchMotionPodUpload.send(contentsOf: missing, side: .left, api: api) {
            #expect(message.hasPrefix("The recording couldn't be read"))
        } else {
            Issue.record("A missing file should fail")
        }
        #expect(api.uploadMotionCalls.count == calls)
    }

    @Test func rowsSayWhatThePodDid() {
        let result = { (status: WatchMotionUploadResult.Status) in
            WatchMotionPodUpload.Outcome.stored(WatchMotionUploadResult(id: 1, side: .left, version: "watch-motion-v2", recordedFromMs: 0,
                                                                        recordedToMs: 0, bins: 0, trimmedBins: 0, status: status))
        }
        #expect(WatchMotionPodUpload.summary(nil, sending: false) == nil)
        #expect(WatchMotionPodUpload.summary(nil, sending: true) == "Sending to pod…")
        #expect(WatchMotionPodUpload.summary(result(.created), sending: false) == "Sent to pod")
        #expect(WatchMotionPodUpload.summary(result(.replaced), sending: false) == "Sent to pod")
        #expect(WatchMotionPodUpload.summary(result(.unchanged), sending: false) == "On pod")
        #expect(WatchMotionPodUpload.summary(.unsupported, sending: false) == "Pod can't store it yet")
        #expect(WatchMotionPodUpload.summary(.failed("x"), sending: false) == "Not sent")
    }

    @Test func coreClientPostsTheFileAndMapsOldPodsAndRefusals() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WatchMotionRouteStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        func client(_ host: String) -> SleepypodCoreClient {
            SleepypodCoreClient(session: session, baseURL: URL(string: "http://\(host):3000"))
        }
        let body = Data(#"{"version":"watch-motion-v2"}"#.utf8)

        let result = try await client("current.test").uploadWatchMotion(side: .right, file: body)
        #expect(result == WatchMotionUploadResult(id: 7, side: .right, version: "watch-motion-v2", recordedFromMs: 1_800_000_000_000,
                                                  recordedToMs: 1_800_000_004_000, bins: 2, trimmedBins: 1, status: .replaced))
        let request = try #require(WatchMotionRouteStub.request(for: "current.test"))
        #expect(request.method == "POST")
        #expect(request.url.path == "/api/biometrics/watch-motion")
        #expect(request.url.query == "side=right")
        #expect(request.contentType == "application/json")
        #expect(request.body == body)

        do {
            _ = try await client("old.test").uploadWatchMotion(side: .left, file: body)
            Issue.record("A pod without the route should throw")
        } catch APIError.notSupported {
        } catch {
            Issue.record("A pod without the route should read as unsupported, not \(error)")
        }
        do {
            _ = try await client("refusing.test").uploadWatchMotion(side: .left, file: body)
            Issue.record("A refused file should throw")
        } catch APIError.serverError(let message) {
            #expect(message == "raw readings are not accepted")
        }
    }
}

/// Answers the watch-motion route by host: a current pod, a pod from before the route, and one refusing the file.
private final class WatchMotionRouteStub: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable {
        let method: String
        let url: URL
        let contentType: String?
        let body: Data
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String: Seen] = [:]
    static func request(for host: String) -> Seen? { lock.withLock { seen[host] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!, host = url.host ?? ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
        }
        let seen = Seen(method: request.httpMethod ?? "", url: url, contentType: request.value(forHTTPHeaderField: "Content-Type"), body: body)
        Self.lock.withLock { Self.seen[host] = seen }
        let (status, payload): (Int, String) = switch host {
        case "current.test":
            (200, #"{"id":7,"side":"right","version":"watch-motion-v2","recordedFromMs":1800000000000,"recordedToMs":1800000004000,"bins":2,"trimmedBins":1,"status":"replaced"}"#)
        case "refusing.test": (400, #"{"error":"raw readings are not accepted"}"#)
        default: (404, "<!DOCTYPE html><title>404</title>")
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
