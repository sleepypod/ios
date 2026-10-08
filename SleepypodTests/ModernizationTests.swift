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
        #expect(samples.count == 17)
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
    var requestedWrites: Set<HKSampleType> = []
    var requestedReads: Set<HKObjectType> = []
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { allowed ? .sharingAuthorized : .sharingDenied }
    func authorize(write: Set<HKSampleType>, read: Set<HKObjectType>) async throws { requestedWrites = write; requestedReads = read }
    func save(_ samples: [HKSample]) async throws {
        if failSave { throw URLError(.cannotWriteToFile) }
        batches.append(samples)
    }
    func sleepSamples(start: Date, end: Date) async -> [HKCategorySample] { [] }
    func quantitySamples(_ type: HKQuantityTypeIdentifier, start: Date, end: Date) async -> [HKQuantitySample] { [] }
}

@Suite("Health sync lifecycle")
@MainActor
struct HealthSyncLifecycleTests {
    @Test func selectedTypesOnlyAndDemoNeverWrites() async {
        let store = FakeHealthStore()
        let defaults = UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")!
        let service = HealthSyncService(store: store, defaults: defaults)
        service.preferences.sleep = false
        service.preferences.hrv = false
        service.preferences.respiration = false
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
