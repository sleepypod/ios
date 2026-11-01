import Testing
import UIKit
import SwiftUI
import HealthKit
@testable import Sleepypod

@Suite("Design behavior")
@MainActor
struct ModernizationTests {
    private func record(closed: Bool = true) throws -> SleepRecord {
        let json = """
        {"id":42,"side":"left","enteredBedAt":1000,"leftBedAt":\(closed ? 1600 : 0),"sleepDurationSeconds":600}
        """
        return try JSONDecoder().decode(SleepRecord.self, from: Data(json.utf8))
    }

    @Test func healthSamplesRespectTypesAndBounds() throws {
        let record = try record()
        let stages: [SleepAnalyzer.SleepStage] = [.wake, .rem, .light, .deep]
        let epochs = stages.enumerated().map { index, stage in
            SleepAnalyzer.SleepEpoch(start: Date(timeIntervalSince1970: 1000 + Double(index) * 60), duration: 60,
                                      stage: stage, heartRate: 62, hrv: 45, breathingRate: 14)
        }
        let samples = HealthSyncService.samples(record: record, epochs: epochs, podID: "pod-a", preferences: .init())
        // In bed, 4 stages, 4 heart rate, 4 breathing, and the 4 HRV readings averaged into one 5-minute window.
        #expect(samples.count == 14)
        let sleep = samples.compactMap { $0 as? HKCategorySample }
        #expect(Set(sleep.map(\.value)) == Set([HKCategoryValueSleepAnalysis.inBed.rawValue,
            HKCategoryValueSleepAnalysis.awake.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue]))
        for sample in samples {
            #expect(sample.device?.name == "sleepypod")
            #expect(sample.device?.localIdentifier == "pod-a-left")
            #expect(sample.metadata?["sleepypod_side"] as? String == "left")
            #expect(sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool == false)
            #expect((sample.metadata?[HKMetadataKeyExternalUUID] as? String)?.hasPrefix("pod-a-left-42-") == true)
            #expect(sample.metadata?[HKMetadataKeySyncIdentifier] is String)
            #expect(sample.startDate >= record.enteredBedDate && sample.endDate <= record.leftBedDate)
        }
        var prefs = HealthSyncService.Preferences()
        prefs.sleep = false; prefs.hrv = false; prefs.respiration = false
        let onlyHR = HealthSyncService.samples(record: record, epochs: epochs, podID: "pod-a", preferences: prefs)
        #expect(onlyHR.count == 4)
        #expect(onlyHR.allSatisfy { $0.sampleType == HKQuantityType(.heartRate) })
        let retry = HealthSyncService.samples(record: record, epochs: epochs, podID: "pod-a", preferences: prefs)
        #expect(onlyHR.map { $0.metadata?[HKMetadataKeySyncIdentifier] as? String } == retry.map { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
    }

    private func vitals(_ minutes: Int, heartRate: (Int) -> Double = { _ in 60 }, hrv: (Int) -> Double? = { _ in 40 }) -> [VitalsRecord] {
        (0..<minutes).map { VitalsRecord(id: $0, side: "left", heartRate: heartRate($0), hrv: hrv($0), breathingRate: 14,
                                         date: Date(timeIntervalSince1970: 1200 + Double($0) * 60)) }
    }

    @Test func hrvIsAveragedIntoClockWindowsOrOneNightlyValue() throws {
        let night = try JSONDecoder().decode(SleepRecord.self, from: Data(#"{"id":7,"side":"left","enteredBedAt":1000,"leftBedAt":3000,"sleepDurationSeconds":2000}"#.utf8))
        // Minutes 0-4 fall in the 1200-1500 window, 5-9 in 1500-1800; one out-of-range reading is ignored.
        let readings = vitals(10, hrv: { $0 == 2 ? 900 : ($0 < 5 ? 30 : 50) })
        let windows = HealthSyncService.hrvWindows(readings, record: night, format: .windows)
        #expect(windows.map(\.value) == [30, 50])
        #expect(windows.map(\.start) == [Date(timeIntervalSince1970: 1200), Date(timeIntervalSince1970: 1500)])
        #expect(windows.allSatisfy { $0.end.timeIntervalSince($0.start) == HealthSyncService.hrvWindow })
        let nightly = HealthSyncService.hrvWindows(readings, record: night, format: .nightly)
        #expect(nightly.count == 1)
        #expect(abs((nightly.first?.value ?? 0) - 370.0 / 9) < 1e-9)
        #expect(nightly.first?.start == night.enteredBedDate && nightly.first?.end == night.leftBedDate)
        var prefs = HealthSyncService.Preferences()
        prefs.hrvFormat = .nightly
        let samples = HealthSyncService.samples(record: night, epochs: [], podID: "pod-a", preferences: prefs, vitals: readings)
        #expect(samples.filter { $0.sampleType == HKQuantityType(.heartRateVariabilitySDNN) }.count == 1)
    }

    @Test func restingHeartRateIsTheLowestFullHalfHour() throws {
        // 90 minutes at 64 bpm with a 30-minute dip to 52 starting at minute 40.
        let readings = vitals(90, heartRate: { (40..<70).contains($0) ? 52 : 64 })
        let resting = try #require(HealthSyncService.restingHeartRate(readings))
        #expect(resting.value == 52)
        #expect(resting.start == Date(timeIntervalSince1970: 1200 + 40 * 60))
        // Too few readings for a half hour gives no resting rate rather than a guess.
        #expect(HealthSyncService.restingHeartRate(vitals(HealthSyncService.restingMinReadings - 1)) == nil)
        let night = try JSONDecoder().decode(SleepRecord.self, from: Data(#"{"id":7,"side":"left","enteredBedAt":1000,"leftBedAt":6800,"sleepDurationSeconds":5000}"#.utf8))
        let samples = HealthSyncService.samples(record: night, epochs: [], podID: "pod-a", preferences: .init(), vitals: readings)
        let written = samples.filter { $0.sampleType == HKQuantityType(.restingHeartRate) }.compactMap { $0 as? HKQuantitySample }
        #expect(written.count == 1)
        #expect(written.first?.quantity.doubleValue(for: .count().unitDivided(by: .minute())) == 52)
        #expect(written.allSatisfy { $0.endDate <= night.leftBedDate })
    }

    @Test func restingHeartRateStaysOffForExistingSetups() throws {
        let saved = try JSONDecoder().decode(HealthSyncService.Preferences.self, from: Data(#"{"sleep":true,"heartRate":true,"hrv":true,"respiration":true}"#.utf8))
        #expect(!saved.restingHeartRate)
        #expect(saved.hrvFormat == .windows)
        #expect(HealthSyncService.Preferences().restingHeartRate)
    }

    @Test func healthDeviceAttributionSeparatesPodsAndSides() throws {
        let left = try record()
        var right = left
        right.side = "right"
        let inputs = [("pod-a", left), ("pod-a", right), ("pod-b", left)]
        let identifiers = inputs.compactMap { pod, record in
            HealthSyncService.samples(record: record, epochs: [], podID: pod, preferences: .init()).first?.device?.localIdentifier
        }
        #expect(identifiers.count == 3)
        #expect(Set(identifiers).count == 3)
    }

    @Test func openNightsDoNotWriteHealthSamples() throws {
        #expect(HealthSyncService.samples(record: try record(closed: false), epochs: [], podID: "pod-a", preferences: .init()).isEmpty)
    }

    @Test func phaseEditsApplyToSelectedDaysAndBothSides() async throws {
        let client = MockClient()
        let manager = ScheduleManager(api: client)
        await manager.fetchSchedules()
        manager.selectedSide = .both
        manager.selectedDays = [.monday, .wednesday]
        #expect(await manager.editPhase(oldTime: "23:30", newTime: "23:45", temperature: 76))
        let saved = try await client.getSchedules()
        for side in Side.allCases {
            #expect(saved.schedule(for: side)[.monday].temperatures["23:45"] == 76)
            #expect(saved.schedule(for: side)[.wednesday].temperatures["23:30"] == nil)
            #expect(saved.schedule(for: side)[.tuesday].temperatures["23:30"] == 68)
        }
        #expect(manager.phases.first?.time == "22:00")
        #expect(await !manager.editPhase(oldTime: "22:00", newTime: "02:00", temperature: 80))
        await manager.applyProfile(.balanced)
        let profiled = try await client.getSchedules()
        for side in Side.allCases {
            #expect(profiled.schedule(for: side)[.monday].temperatures["22:00"] == 78)
            #expect(profiled.schedule(for: side)[.monday].temperatures["02:00"] == 74)
            #expect(profiled.schedule(for: side)[.wednesday].temperatures["22:00"] == 78)
            #expect(profiled.schedule(for: side)[.tuesday].temperatures["22:00"] == 70)
        }
    }
}

@MainActor
private final class FakeHealthStore: HealthSyncStore {
    var available = true
    var allowed = true
    var failSave = false
    var batches: [[HKSample]] = []
    var deletes: [(deviceID: String, start: Date, end: Date, olderThan: Int?)] = []
    var events: [String] = []
    var requestedWrites: Set<HKSampleType> = []
    var requestedReads: Set<HKObjectType> = []
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { allowed ? .sharingAuthorized : .sharingDenied }
    func authorize(write: Set<HKSampleType>, read: Set<HKObjectType>) async throws { requestedWrites = write; requestedReads = read }
    func save(_ samples: [HKSample]) async throws {
        if failSave { throw URLError(.cannotWriteToFile) }
        batches.append(samples)
        events.append("save")
    }
    func delete(types: Set<HKSampleType>, deviceID: String, start: Date, end: Date, olderThan version: Int?) async throws {
        deletes.append((deviceID, start, end, version))
        events.append("delete")
    }
    var sweeps: [(types: Set<HKSampleType>, olderThan: Int, since: Date)] = []
    func deleteAll(types: Set<HKSampleType>, olderThan version: Int, since start: Date) async throws {
        sweeps.append((types, version, start))
        events.append("deleteAll")
    }
    func sleepSamples(start: Date, end: Date) async -> [HKCategorySample] { [] }
    func quantitySamples(_ type: HKQuantityTypeIdentifier, start: Date, end: Date) async -> [HKQuantitySample] { [] }
}

@Suite("Health sync lifecycle")
@MainActor
struct HealthSyncLifecycleTests {
    @Test func deniedAccessIsOnlyReportedAfterARefusalOnAnAvailableStore() async {
        let store = FakeHealthStore()
        let defaults = UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!
        let service = HealthSyncService(store: store, defaults: defaults)
        #expect(!service.authorizationDenied)
        store.allowed = false
        #expect(service.authorizationDenied)
        store.available = false
        #expect(!service.authorizationDenied, "nothing to open in Settings where Health does not exist")
        store.available = true
        service.preferences.sleep = false; service.preferences.heartRate = false
        service.preferences.hrv = false; service.preferences.respiration = false; service.preferences.restingHeartRate = false
        #expect(!service.authorizationDenied, "no write types means no sheet was ever refused")
    }

    @Test func selectedTypesOnlyAndDemoNeverWrites() async {
        let store = FakeHealthStore()
        let defaults = UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!
        let service = HealthSyncService(store: store, defaults: defaults)
        service.preferences.sleep = false
        service.preferences.hrv = false
        service.preferences.respiration = false
        service.preferences.restingHeartRate = false
        service.preferences.readSleep = false
        service.preferences.readVitals = false
        #expect(await service.requestAuthorization())
        #expect(store.requestedWrites == [HKQuantityType(.heartRate)])
        #expect(store.requestedReads.isEmpty)
        service.preferences.readVitals = true
        #expect(await service.requestAuthorization())
        #expect(store.requestedReads == [HKQuantityType(.heartRate), HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.respiratoryRate)])
        await service.syncRecent(api: MockClient(), podID: "test-pod", side: .left, demo: true)
        #expect(store.batches.isEmpty)
    }

    @Test func receiptsOnlyAfterSuccessfulWriteAndRetriesAreIdempotent() async {
        let store = FakeHealthStore()
        let defaults = UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!
        let service = HealthSyncService(store: store, defaults: defaults)
        service.enabled = true
        let api = MockClient()
        store.failSave = true
        await service.syncRecent(api: api, podID: "test-pod", side: .right, demo: false)
        #expect(service.receipts.isEmpty)
        #expect(!service.failures.isEmpty)
        store.failSave = false
        await service.syncRecent(api: api, podID: "test-pod", side: .right, demo: false)
        let count = store.batches.count
        #expect(count > 0)
        #expect(service.receipts.count == count)
        #expect(store.batches.flatMap { $0 }.allSatisfy { ($0.metadata?[HKMetadataKeyExternalUUID] as? String)?.hasPrefix("test-pod-right-") == true })
        await service.syncRecent(api: api, podID: "test-pod", side: .right, demo: false)
        #expect(store.batches.count == count)
        let restored = HealthSyncService(store: store, defaults: defaults)
        await restored.syncRecent(api: api, podID: "test-pod", side: .right, demo: false)
        #expect(store.batches.count == count)
    }

    @Test func syncableRecordsExcludeFragmentsAndCappedSessions() throws {
        func record(_ duration: Int) throws -> SleepRecord {
            try JSONDecoder().decode(SleepRecord.self, from: Data("""
            {"id":1,"side":"left","enteredBedAt":1000,"leftBedAt":\(1000 + duration),"sleepDurationSeconds":\(duration)}
            """.utf8))
        }
        #expect(!HealthSyncService.isSyncable(try record(15 * 60)))
        #expect(HealthSyncService.isSyncable(try record(8 * 3600)))
        #expect(!HealthSyncService.isSyncable(try record(16 * 3600)))
    }

    @Test func eachNightDropsOnlyOlderSamplesAfterItIsWritten() async throws {
        let store = FakeHealthStore()
        let service = HealthSyncService(store: store, defaults: UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!)
        service.enabled = true
        await service.syncRecent(api: MockClient(), podID: "test-pod", side: .left, demo: false)
        #expect(!store.batches.isEmpty)
        #expect(store.events == Array(repeating: ["save", "delete"], count: store.batches.count).flatMap { $0 })
        for (delete, batch) in zip(store.deletes, store.batches) {
            #expect(delete.deviceID == "test-pod-left")
            #expect(batch.allSatisfy { $0.startDate >= delete.start && $0.startDate < delete.end })
            #expect(delete.olderThan != nil)
            #expect(batch.allSatisfy { $0.metadata?[HKMetadataKeySyncVersion] as? Int == delete.olderThan })
        }
    }

    @Test func receiptsFromAnEarlierSyncVersionAreRewritten() async throws {
        let store = FakeHealthStore()
        let defaults = UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!
        let api = MockClient()
        let records = try await api.getSleepRecords(side: .left, start: nil, end: nil)
        let legacy = Dictionary(uniqueKeysWithValues: records.map {
            (HealthSyncService.recordKey(podID: "test-pod", record: $0),
             HealthSyncService.Receipt(date: Date(), signature: HealthSyncService.Preferences().signature,
                                       closedAt: $0.leftBedDate, enteredAt: $0.enteredBedDate))
        })
        defaults.set(try JSONEncoder().encode(legacy), forKey: "healthSyncReceipts")
        let service = HealthSyncService(store: store, defaults: defaults)
        service.enabled = true
        await service.syncRecent(api: api, podID: "test-pod", side: .left, demo: false)
        #expect(!store.batches.isEmpty)
        // Mock nights are relative to the clock, so the latest may still be open and keep its legacy receipt.
        let rewritten = service.receipts.values.filter { $0.signature == HealthSyncService.receiptSignature(service.preferences) }
        #expect(rewritten.count == store.batches.count)
    }

    @Test func excludedRecordsAreRemovedFromHealthOnlyIfPreviouslyWritten() async throws {
        let store = FakeHealthStore()
        let defaults = UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!
        let api = ExcludedRecordsClient()
        let records = try await api.getSleepRecords(side: .left, start: nil, end: nil)
        let written = records[0]
        defaults.set(try JSONEncoder().encode([HealthSyncService.recordKey(podID: "test-pod", record: written):
            HealthSyncService.Receipt(date: Date(), signature: "old", closedAt: written.leftBedDate, enteredAt: written.enteredBedDate)]),
                     forKey: "healthSyncReceipts")
        let service = HealthSyncService(store: store, defaults: defaults)
        service.enabled = true
        await service.syncRecent(api: api, podID: "test-pod", side: .left, demo: false)
        #expect(store.batches.isEmpty)
        #expect(store.deletes.count == 1)
        #expect(store.deletes.first?.start == written.enteredBedDate && store.deletes.first?.end == written.leftBedDate)
        #expect(store.deletes.first?.olderThan == nil)
        #expect(service.receipts.isEmpty)
        #expect(HealthSyncService(store: store, defaults: defaults).receipts.isEmpty)
    }

    @Test func rebuildRewritesEveryNightThenSweepsEverythingOlder() async throws {
        let store = FakeHealthStore()
        let service = HealthSyncService(store: store, defaults: UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!)
        service.enabled = true
        let api = MockClient()
        await service.syncRecent(api: api, podID: "test-pod", side: .left, demo: false)
        let nights = store.batches.count
        #expect(nights > 0)
        #expect(await service.rebuild(api: api, podID: "test-pod", side: .left, demo: false))
        // Already-synced nights are written again rather than skipped by their receipts.
        #expect(store.batches.count == nights * 2)
        #expect(store.events.last == "deleteAll")
        let sweep = try #require(store.sweeps.first)
        #expect(store.batches.suffix(nights).flatMap { $0 }.allSatisfy { ($0.metadata?[HKMetadataKeySyncVersion] as? Int ?? 0) >= sweep.olderThan })
        #expect(store.batches.prefix(nights).flatMap { $0 }.allSatisfy { ($0.metadata?[HKMetadataKeySyncVersion] as? Int ?? .max) < sweep.olderThan })
        #expect(service.receipts.count == nights)
        #expect(service.rebuildProgress == nil && !service.isSyncing)
        // A type switched off since an earlier sync still gets swept.
        service.preferences.hrv = false
        #expect(await service.rebuild(api: api, podID: "test-pod", side: .left, demo: false))
        #expect(store.sweeps.last?.types == Set(HealthSyncService.allWriteTypes))
        // A chosen start limits the sweep, so earlier nights are kept.
        let since = Date().addingTimeInterval(-3 * 86400)
        #expect(await service.rebuild(api: api, podID: "test-pod", side: .left, since: since, demo: false))
        #expect(store.sweeps.last?.since == since)
    }

    @Test func failedRebuildKeepsOlderHealthData() async {
        let store = FakeHealthStore()
        let service = HealthSyncService(store: store, defaults: UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!)
        service.enabled = true
        store.failSave = true
        #expect(await !service.rebuild(api: MockClient(), podID: "test-pod", side: .left, demo: false))
        #expect(store.sweeps.isEmpty)
        #expect(!service.failures.isEmpty)
        #expect(await !service.rebuild(api: MockClient(), podID: "test-pod", side: .left, demo: true))
    }

    @Test func receiptsCarryTheAnalyzerVersion() {
        #expect(HealthSyncService.receiptSignature(.init()).contains("-a\(SleepAnalyzer.version)-"))
    }

    @Test func longWindowsAreFetchedByWeekAndCappedWeeksByDay() async throws {
        let api = PagedRecordsClient()
        let end = Date()
        let start = end.addingTimeInterval(-21 * 86400)
        let records = try await HealthSyncService.sleepRecords(api: api, side: .left, start: start, end: end)
        // Weeks 1 and 3 return a few nights; week 2 hits the cap and is refetched as 7 days.
        #expect(api.requests.count == 3 + 7)
        #expect(api.requests.allSatisfy { $0.end.timeIntervalSince($0.start) <= 7 * 86400 })
        #expect(Set(records.map(\.id)).count == records.count)
    }

    @Test func deniedWritesDoNotProduceReceipts() async {
        let store = FakeHealthStore()
        store.allowed = false
        let service = HealthSyncService(store: store, defaults: UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!)
        service.enabled = true
        await service.syncRecent(api: MockClient(), podID: "test-pod", side: .left, demo: false)
        #expect(store.batches.isEmpty)
        #expect(service.receipts.isEmpty)
    }
}

@Suite("Bundled typography")
@MainActor
struct TypographyTests {
    @Test func plexFacesAreRegistered() {
        for weight: Font.Weight in [.light, .regular, .medium] {
            #expect(UIFont(name: Font.monoPostScriptName(weight: weight), size: 13) != nil)
        }
    }
}

@Suite("Design formatting")
@MainActor
struct DesignFormattingTests {
    private func epoch(_ start: TimeInterval, _ duration: TimeInterval, _ stage: SleepAnalyzer.SleepStage) -> SleepAnalyzer.SleepEpoch {
        SleepAnalyzer.SleepEpoch(start: Date(timeIntervalSince1970: start), duration: duration, stage: stage,
                                 heartRate: 55, hrv: nil, breathingRate: nil)
    }

    @Test func stageEpochsMergeIntoContinuousSegments() {
        let epochs = [epoch(0, 60, .light), epoch(120, 60, .light), epoch(180, 60, .deep), epoch(2000, 60, .rem)]
        let segments = SleepStagesTimelineView.segments(epochs)
        #expect(segments.map(\.stage) == [.light, .deep, .rem])
        #expect(segments[0].end.timeIntervalSince1970 == 180)
        #expect(segments[1].end.timeIntervalSince1970 == 240)
    }

    @Test func scheduledTemperaturesUseHoldingBand() {
        #expect(TempColor.forScheduled(76) == Theme.cool)
        #expect(TempColor.forScheduled(78) == Theme.neutral)
        #expect(TempColor.forScheduled(82) == Theme.neutral)
        #expect(TempColor.forScheduled(84) == Theme.warm)
    }

    @Test func timesFollowSourceCopy() {
        #expect(DisplayTime.tick(minutes: 120) == "2 AM")
        #expect(DisplayTime.tick(minutes: 22 * 60 + 30) == "10:30 PM")
        #expect(DisplayTime.clock("00:05") == "12:05 AM")
        #expect(DisplayTime.duration(7 * 3600 + 9 * 60) == "7h 09m")
    }

    @Test func phasesAreNamedByPosition() {
        #expect(ScheduleManager.phaseLabel(index: 0, count: 5).0 == "Bedtime")
        #expect(ScheduleManager.phaseLabel(index: 1, count: 5).0 == "Deep")
        #expect(ScheduleManager.phaseLabel(index: 2, count: 5).0 == "Late night")
        #expect(ScheduleManager.phaseLabel(index: 4, count: 5).0 == "Pre-wake")
    }
}

@Suite("Night and Dawn")
@MainActor
struct NightPhasesTests {
    @Test func decodesCoreResponse() throws {
        let json = """
        {"draft":false,"day":"monday","days":["monday","tuesday","wednesday","thursday","friday"],
         "night":{"temperatureF":73.25,"start":"22:00","end":"06:00","minutes":480,"times":["22:00","23:00","03:00"]},
         "dawn":{"temperatureF":84,"start":"06:00","end":"06:00","minutes":30,"times":["06:00"]}}
        """
        let phases = try JSONDecoder().decode(NightPhases.self, from: Data(json.utf8))
        #expect(phases.phase(.night)?.times.count == 3)
        #expect(phases.daysSummary == "Weekdays")
    }

    @Test func summarizesDaysLikeTheWeb() throws {
        func summary(_ days: [DayOfWeek]) throws -> String {
            let night = NightPhase(temperatureF: 72, start: "22:00", end: "06:00", minutes: 480, times: ["22:00"])
            return NightPhases(draft: false, day: days[0], days: days, night: night, dawn: nil).daysSummary
        }
        #expect(try summary(DayOfWeek.allCases) == "Daily")
        #expect(try summary([.saturday, .sunday]) == "Weekends")
        #expect(try summary([.monday, .tuesday, .wednesday, .saturday]) == "Mon–Wed, Sat")
        #expect(try summary([.saturday, .sunday, .monday]) == "Sat–Mon")
    }

    @Test func stepsInDisplayDegrees() {
        #expect(NightPhasesStore.step(72, delta: 1, format: .fahrenheit) == 73)
        #expect(NightPhasesStore.step(72, delta: 1, format: .celsius) == 73)
        #expect(NightPhasesStore.step(110, delta: 1, format: .fahrenheit) == 110)
    }
}

/// The second week of a three-week window returns the core's default cap; every other request returns two nights.
private final class PagedRecordsClient: MockAPIClient, @unchecked Sendable {
    var requests: [(start: Date, end: Date)] = []
    private var firstWeek: Date?
    override func getSleepRecords(side: Side?, start: Date?, end: Date?) async throws -> [SleepRecord] {
        guard let start, let end else { return [] }
        requests.append((start, end))
        if firstWeek == nil { firstWeek = start }
        let week = Int(start.timeIntervalSince(firstWeek!) / (7 * 86400))
        let isWeek = end.timeIntervalSince(start) > 86400
        let count = week == 1 && isWeek ? HealthSyncService.recordsPageLimit : 2
        let base = Int(start.timeIntervalSince1970)
        return try (0..<count).map { i in
            try JSONDecoder().decode(SleepRecord.self, from: Data("""
            {"id":\(base + i),"side":"left","enteredBedAt":\(base + i * 60),"leftBedAt":\(base + i * 60 + 3600),"sleepDurationSeconds":3600}
            """.utf8))
        }
    }
}

/// A capped 16 h session (previously synced) and a 10 min fragment, both of which sync must skip.
private final class ExcludedRecordsClient: MockAPIClient, @unchecked Sendable {
    override func getSleepRecords(side: Side?, start: Date?, end: Date?) async throws -> [SleepRecord] {
        let now = Int(Date().timeIntervalSince1970)
        return try [(1, now - 20 * 3600, now - 4 * 3600), (2, now - 3 * 3600, now - 3 * 3600 + 600)].map { id, entered, left in
            try JSONDecoder().decode(SleepRecord.self, from: Data("""
            {"id":\(id),"side":"left","enteredBedAt":\(entered),"leftBedAt":\(left),"sleepDurationSeconds":\(left - entered)}
            """.utf8))
        }
    }
}
