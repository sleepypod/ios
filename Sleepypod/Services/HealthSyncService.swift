import Foundation
import HealthKit
import Observation

@MainActor
protocol HealthSyncStore {
    var available: Bool { get }
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func authorize(write: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    func save(_ samples: [HKSample]) async throws
    func sleepSamples(start: Date, end: Date) async -> [HKCategorySample]
    func quantitySamples(_ type: HKQuantityTypeIdentifier, start: Date, end: Date) async -> [HKQuantitySample]
}

@MainActor
final class SystemHealthSyncStore: HealthSyncStore {
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { store.authorizationStatus(for: type) }
    func authorize(write: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: write, read: read)
    }
    func save(_ samples: [HKSample]) async throws { try await store.save(samples) }
    func sleepSamples(start: Date, end: Date) async -> [HKCategorySample] {
        await HealthSyncService.querySleepSamples(store: store, start: start, end: end)
    }
    func quantitySamples(_ type: HKQuantityTypeIdentifier, start: Date, end: Date) async -> [HKQuantitySample] {
        await HealthSyncService.querySamples(store: store, type: HKQuantityType(type), start: start, end: end)
    }
}

@MainActor
@Observable
final class HealthSyncService {
    struct Preferences: Codable, Equatable {
        var sleep = true
        var heartRate = true
        var hrv = true
        var respiration = true
        var readSleep = true
        var readVitals = true
        var signature: String { "\(sleep)-\(heartRate)-\(hrv)-\(respiration)" }

        init() {}
        // Keys added after a build shipped decode as their defaults rather than resetting every preference.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sleep = try c.decodeIfPresent(Bool.self, forKey: .sleep) ?? true
            heartRate = try c.decodeIfPresent(Bool.self, forKey: .heartRate) ?? true
            hrv = try c.decodeIfPresent(Bool.self, forKey: .hrv) ?? true
            respiration = try c.decodeIfPresent(Bool.self, forKey: .respiration) ?? true
            readSleep = try c.decodeIfPresent(Bool.self, forKey: .readSleep) ?? true
            readVitals = try c.decodeIfPresent(Bool.self, forKey: .readVitals) ?? true
        }
    }
    struct Receipt: Codable {
        let date: Date
        let signature: String
        let closedAt: Date
        let enteredAt: Date?
    }
    var preferences: Preferences {
        didSet { persistence.set(try? JSONEncoder().encode(preferences), forKey: "healthSyncPreferences") }
    }
    var enabled: Bool {
        didSet { persistence.set(enabled, forKey: "healthSyncEnabled") }
    }
    private(set) var receipts: [String: Receipt]
    private(set) var failures: [String: String] = [:]
    private(set) var isSyncing = false
    var authorizationError: String?
    private let store: any HealthSyncStore
    private let persistence: UserDefaults

    init(store: any HealthSyncStore = SystemHealthSyncStore(), defaults: UserDefaults = .standard) {
        self.store = store
        persistence = defaults
        preferences = defaults.data(forKey: "healthSyncPreferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        receipts = defaults.data(forKey: "healthSyncReceipts").flatMap { try? JSONDecoder().decode([String: Receipt].self, from: $0) } ?? [:]
        enabled = defaults.bool(forKey: "healthSyncEnabled")
    }

    var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if preferences.sleep { types.insert(HKCategoryType(.sleepAnalysis)) }
        if preferences.heartRate { types.insert(HKQuantityType(.heartRate)) }
        if preferences.hrv { types.insert(HKQuantityType(.heartRateVariabilitySDNN)) }
        if preferences.respiration { types.insert(HKQuantityType(.respiratoryRate)) }
        return types
    }

    static let vitalsReadTypes: [HKQuantityTypeIdentifier] = [.heartRate, .heartRateVariabilitySDNN, .respiratoryRate]

    var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if preferences.readSleep { types.insert(HKCategoryType(.sleepAnalysis)) }
        if preferences.readVitals { types.formUnion(Self.vitalsReadTypes.map { HKQuantityType($0) }) }
        return types
    }

    var hasWriteAuthorization: Bool {
        enabled && writeTypes.contains { store.authorizationStatus(for: $0) == .sharingAuthorized }
    }

    func requestAuthorization() async -> Bool {
        guard store.available else {
            authorizationError = "Apple Health is unavailable on this device."
            return false
        }
        do {
            try await store.authorize(write: writeTypes, read: readTypes)
            // Completing the sheet does not prove access was granted. Each write is checked separately.
            enabled = true
            authorizationError = nil
            return true
        } catch {
            authorizationError = error.localizedDescription
            return false
        }
    }

    static func recordKey(podID: String, record: SleepRecord) -> String { "\(podID)-\(record.side)-\(record.id)" }

    func receipt(podID: String, record: SleepRecord) -> Receipt? {
        guard enabled, !writeTypes.isEmpty,
              writeTypes.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }),
              let receipt = receipts[Self.recordKey(podID: podID, record: record)],
              receipt.signature == preferences.signature, receipt.closedAt == record.leftBedDate, receipt.enteredAt == record.enteredBedDate else { return nil }
        return receipt
    }

    func syncRecent(api: SleepypodProtocol, podID: String, side: Side, demo: Bool) async {
        guard enabled, !demo, !isSyncing, !podID.isEmpty, store.available, !writeTypes.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        let requestedPreferences = preferences
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        do {
            let records = try await api.getSleepRecords(side: side, start: start, end: end)
            for record in records where record.side == side.rawValue && record.enteredBedDate.timeIntervalSince1970 > 0 && record.leftBedDate > record.enteredBedDate && record.leftBedDate <= end {
                let key = Self.recordKey(podID: podID, record: record)
                guard receipt(podID: podID, record: record) == nil else { continue }
                do {
                    guard !Task.isCancelled, enabled, preferences == requestedPreferences else { return }
                    guard writeTypes.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else {
                        failures[key] = "Allow the selected write types in Apple Health."
                        continue
                    }
                    let vitals = try await api.getVitals(side: side, start: record.enteredBedDate, end: record.leftBedDate)
                    let movement = try await api.getMovement(side: side, start: record.enteredBedDate, end: record.leftBedDate)
                    let calibration = try? await api.getCalibrationStatus(side: side)
                    let analyzer = SleepAnalyzer()
                    analyzer.analyze(vitals: vitals.filter { $0.side == side.rawValue && $0.date >= record.enteredBedDate && $0.date < record.leftBedDate },
                                     movement: movement, calibrationQuality: calibration?.piezo?.qualityScore ?? 0)
                    let filtered = analyzer.filterOutliers(vitals: vitals.filter { $0.side == side.rawValue && $0.date >= record.enteredBedDate && $0.date < record.leftBedDate })
                    guard !Task.isCancelled, enabled, preferences == requestedPreferences else { return }
                    guard !filtered.isEmpty, !preferences.sleep || !analyzer.stages.isEmpty else {
                        failures[key] = "Waiting for enough vitals to analyze this night."
                        continue
                    }
                    let samples = Self.samples(record: record, epochs: analyzer.stages, podID: podID, preferences: requestedPreferences, vitals: filtered)
                    guard !samples.isEmpty else { continue }
                    try await store.save(samples)
                    receipts[key] = Receipt(date: Date(), signature: requestedPreferences.signature, closedAt: record.leftBedDate, enteredAt: record.enteredBedDate)
                    failures[key] = nil
                    persistence.set(try JSONEncoder().encode(receipts), forKey: "healthSyncReceipts")
                } catch { failures[key] = error.localizedDescription }
            }
        } catch { authorizationError = error.localizedDescription }
    }

    // Sync identifiers, unlike ExternalUUID alone, make retries idempotent in HealthKit.
    // Incrementing the version permits a corrected record to replace earlier samples.
    static func samples(record: SleepRecord, epochs: [SleepAnalyzer.SleepEpoch], podID: String, preferences: Preferences, vitals: [VitalsRecord]? = nil) -> [HKSample] {
        guard record.enteredBedDate.timeIntervalSince1970 > 0, record.leftBedDate > record.enteredBedDate else { return [] }
        let key = recordKey(podID: podID, record: record)
        let version = Int(Date().timeIntervalSince1970 * 1000)
        func metadata(_ epoch: String, type: String) -> [String: Any] {
            [HKMetadataKeyExternalUUID: "\(key)-\(epoch)", HKMetadataKeyWasUserEntered: false,
             HKMetadataKeySyncIdentifier: "\(key)-\(epoch)-\(type)", HKMetadataKeySyncVersion: version]
        }
        var result: [HKSample] = []
        if preferences.sleep {
            result.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: record.enteredBedDate, end: record.leftBedDate, metadata: metadata("inBed", type: "sleep")))
        }
        for epoch in epochs where epoch.start >= record.enteredBedDate && epoch.start < record.leftBedDate {
            let end = min(record.leftBedDate, epoch.start.addingTimeInterval(epoch.duration))
            guard end > epoch.start else { continue }
            let id = String(Int(epoch.start.timeIntervalSince1970))
            if preferences.sleep {
                result.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: stageValue(epoch.stage),
                    start: epoch.start, end: end, metadata: metadata(id, type: "sleep")))
            }
        }
        let values = vitals ?? epochs.map {
            VitalsRecord(id: Int($0.start.timeIntervalSince1970), side: record.side, heartRate: $0.heartRate,
                         hrv: $0.hrv, breathingRate: $0.breathingRate, date: $0.start)
        }
        for vital in values where vital.side == record.side && vital.date >= record.enteredBedDate && vital.date < record.leftBedDate {
            let end = min(record.leftBedDate, vital.date.addingTimeInterval(60))
            let id = String(Int(vital.date.timeIntervalSince1970))
            let quantities: [(Bool, HKQuantityTypeIdentifier, Double?, HKUnit, ClosedRange<Double>)] = [
                (preferences.heartRate, .heartRate, vital.heartRate, .count().unitDivided(by: .minute()), 45...130),
                (preferences.hrv, .heartRateVariabilitySDNN, vital.hrv, .secondUnit(with: .milli), 0.001...300),
                (preferences.respiration, .respiratoryRate, vital.breathingRate, .count().unitDivided(by: .minute()), 8...25)
            ]
            for (enabled, type, value, unit, range) in quantities {
                if enabled, let value, value.isFinite, range.contains(value) {
                    result.append(HKQuantitySample(type: HKQuantityType(type), quantity: HKQuantity(unit: unit, doubleValue: value),
                        start: vital.date, end: end, metadata: metadata(id, type: type.rawValue)))
                }
            }
        }
        return result
    }

    static func stageValue(_ stage: SleepAnalyzer.SleepStage) -> Int {
        switch stage {
        case .wake: HKCategoryValueSleepAnalysis.awake.rawValue
        case .rem: HKCategoryValueSleepAnalysis.asleepREM.rawValue
        case .light: HKCategoryValueSleepAnalysis.asleepCore.rawValue
        case .deep: HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        }
    }

    static func stage(for value: Int) -> SleepAnalyzer.SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .awake: .wake
        case .asleepREM: .rem
        case .asleepCore: .light
        case .asleepDeep: .deep
        default: nil
        }
    }

    // Only what the Watch itself recorded counts; sleepypod's own writes are never compared against themselves.
    static func isWatch(_ sample: HKSample) -> Bool {
        sample.sourceRevision.productType?.hasPrefix("Watch") == true
            && sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    static func watchStages(_ samples: [HKCategorySample]) -> [WatchComparison.StageSample] {
        samples.filter(isWatch).compactMap { sample in
            stage(for: sample.value).map { WatchComparison.StageSample(start: sample.startDate, end: sample.endDate, stage: $0) }
        }
    }

    static func watchReadings(_ samples: [HKQuantitySample], unit: HKUnit) -> [WatchComparison.Reading] {
        samples.filter(isWatch).map { WatchComparison.Reading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    /// Agreement for the whole week plus one value per night, from a single Health read.
    func weekAgreement(nights: [[SleepAnalyzer.SleepEpoch]]) async -> (overall: Double?, nightly: [Double?]) {
        let all = nights.flatMap { $0 }
        guard enabled, preferences.readSleep, let start = all.map(\.start).min(),
              let end = all.map({ $0.start.addingTimeInterval($0.duration) }).max() else { return (nil, nights.map { _ in nil }) }
        let watch = Self.watchStages(await store.sleepSamples(start: start, end: end))
        return (WatchComparison.stageAgreement(epochs: all, watch: watch).percent,
                nights.map { WatchComparison.stageAgreement(epochs: $0, watch: watch).percent })
    }

    func watchComparison(record: SleepRecord, epochs: [SleepAnalyzer.SleepEpoch], vitals: [VitalsRecord]) async -> WatchComparison? {
        guard enabled, preferences.readSleep || preferences.readVitals, store.available,
              record.leftBedDate > record.enteredBedDate else { return nil }
        let start = record.enteredBedDate, end = record.leftBedDate
        let stages = preferences.readSleep ? Self.watchStages(await store.sleepSamples(start: start, end: end)) : []
        var heartRate: [WatchComparison.Reading] = [], hrv: [WatchComparison.Reading] = [], breathing: [WatchComparison.Reading] = []
        if preferences.readVitals {
            heartRate = Self.watchReadings(await store.quantitySamples(.heartRate, start: start, end: end), unit: .count().unitDivided(by: .minute()))
            hrv = Self.watchReadings(await store.quantitySamples(.heartRateVariabilitySDNN, start: start, end: end), unit: .secondUnit(with: .milli))
            breathing = Self.watchReadings(await store.quantitySamples(.respiratoryRate, start: start, end: end), unit: .count().unitDivided(by: .minute()))
        }
        return WatchComparison.build(epochs: epochs, vitals: vitals, watchStages: stages,
                                     watchHeartRate: heartRate, watchHRV: hrv, watchBreathing: breathing)
    }

    func sleepSamples(start: Date, end: Date) async -> [HKCategorySample] {
        guard enabled, preferences.readSleep else { return [] }
        return await store.sleepSamples(start: start, end: end)
    }

    static func queryScheduleTimes(store: HKHealthStore, start: Date, end: Date) async -> (bed: Date, wake: Date)? {
        let samples = await querySleepSamples(store: store, start: start, end: end)
        return scheduleTimes(from: samples)
    }

    static func scheduleTimes(from samples: [HKCategorySample]) -> (bed: Date, wake: Date)? {
        let external = samples.filter { $0.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier }
        if let inBed = external.first(where: { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }) {
            return (inBed.startDate, inBed.endDate)
        }
        let asleepValues = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                            HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let asleep = external.filter { asleepValues.contains($0.value) }.sorted { $0.startDate > $1.startDate }
        guard let latest = asleep.first else { return nil }
        var bed = latest.startDate
        let wake = latest.endDate
        for sample in asleep.dropFirst() {
            guard bed.timeIntervalSince(sample.endDate) <= 3600 else { break }
            bed = min(bed, sample.startDate)
        }
        return (bed, wake)
    }

    func inferredSchedule() async -> (bed: Date, wake: Date)? {
        guard enabled, preferences.readSleep else { return nil }
        let samples = await store.sleepSamples(start: Date().addingTimeInterval(-7 * 86400), end: Date())
        return Self.scheduleTimes(from: samples)
    }

    static func querySleepSamples(store: HKHealthStore, start: Date, end: Date) async -> [HKCategorySample] {
        await querySamples(store: store, type: HKCategoryType(.sleepAnalysis), start: start, end: end)
    }

    static func querySamples<S: HKSample>(store: HKHealthStore, type: HKSampleType, start: Date, end: Date) async -> [S] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                    continuation.resume(returning: samples as? [S] ?? [])
                }
            store.execute(query)
        }
    }
}
