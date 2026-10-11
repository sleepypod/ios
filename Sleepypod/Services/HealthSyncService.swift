import BackgroundTasks
import Foundation
import HealthKit
import Observation
import UIKit

@MainActor
protocol HealthSyncStore {
    var available: Bool { get }
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func authorize(write: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    func save(_ samples: [HKSample]) async throws
    func delete(types: Set<HKSampleType>, deviceID: String, start: Date, end: Date, olderThan version: Int?) async throws
    func deleteAll(types: Set<HKSampleType>, olderThan version: Int) async throws
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
    // HealthKit only lets an app delete its own samples; the device match keeps other pods and sides out.
    func delete(types: Set<HKSampleType>, deviceID: String, start: Date, end: Date, olderThan version: Int?) async throws {
        var predicates = [
            HKQuery.predicateForObjects(from: .default()),
            HKQuery.predicateForObjects(withDeviceProperty: HKDevicePropertyKeyLocalIdentifier, allowedValues: [deviceID]),
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        ]
        if let version {
            predicates.append(HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncVersion,
                                                          operatorType: .lessThan, value: version))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        for type in types {
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }
    // Every pod, side and night this app wrote before `version`.
    func deleteAll(types: Set<HKSampleType>, olderThan version: Int) async throws {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: .default()),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncVersion, operatorType: .lessThan, value: version)
        ])
        for type in types {
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }
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
    private(set) var rebuildProgress: (done: Int, total: Int)?
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

    static let allWriteTypes: [HKSampleType] = [HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRate),
                                                HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.respiratoryRate)]

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
            Log.health.info("HealthKit is unavailable on this device")
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
            Log.health.error("Health authorization failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    static func recordKey(podID: String, record: SleepRecord) -> String { "\(podID)-\(record.side)-\(record.id)" }
    static func deviceID(podID: String, record: SleepRecord) -> String { "\(podID)-\(record.side)" }

    /// Bump when the samples written for a night change, so every synced night is rewritten once.
    /// v2: full-night vitals (previously truncated to the last 288 rows), capped and fragment records dropped.
    static let syncVersion = 2
    static func receiptSignature(_ preferences: Preferences) -> String {
        "v\(syncVersion)-a\(SleepAnalyzer.version)-\(preferences.signature)"
    }

    /// The pod force-closes a session after 16 h (MAX_SESSION_S in sleep-detector); those are stuck presence, not sleep.
    static let maxSessionDuration: TimeInterval = 16 * 3600
    static let minSessionDuration: TimeInterval = 20 * 60
    static func isSyncable(_ record: SleepRecord) -> Bool {
        let duration = record.leftBedDate.timeIntervalSince(record.enteredBedDate)
        return duration >= minSessionDuration && duration < maxSessionDuration
    }

    func receipt(podID: String, record: SleepRecord) -> Receipt? {
        guard enabled, !writeTypes.isEmpty,
              writeTypes.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }),
              let receipt = receipts[Self.recordKey(podID: podID, record: record)],
              receipt.signature == Self.receiptSignature(preferences), receipt.closedAt == record.leftBedDate, receipt.enteredAt == record.enteredBedDate else { return nil }
        return receipt
    }

    /// BGTaskScheduler identifier; must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    nonisolated static let backgroundTaskID = "com.jonathanng.sleepypod.health-sync"

    /// Ask iOS to wake the app later to sync finished nights. iOS picks the actual time,
    /// usually around when the phone is in use, so this is a floor, not a schedule.
    nonisolated static func scheduleBackgroundSync(after interval: TimeInterval = 60 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.health.error("Couldn't schedule background Health sync: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Background refresh entry point. Rebuilds the pod and side from saved settings, since
    /// no UI is running. Skips while the phone is locked: Health data is encrypted then and
    /// writes fail, so the next wake-up retries instead of recording a failure.
    func syncInBackground() async {
        guard enabled, UIApplication.shared.isProtectedDataAvailable else { return }
        let backend = APIBackend.current
        guard !backend.isDemo,
              let address = UserDefaults.standard.string(forKey: "podIPAddress"), !address.isEmpty else { return }
        let side = Side(rawValue: UserDefaults.standard.string(forKey: "userDefaultSide") ?? "") ?? .left
        await syncRecent(api: backend.createClient(), podID: SettingsManager.registerPodIdentity(address: address),
                         side: side, demo: false)
        Log.health.info("Background Health sync finished")
    }

    static let recentDays = 7
    static let rebuildDays = 90

    func syncRecent(api: SleepypodProtocol, podID: String, side: Side, demo: Bool) async {
        guard enabled, !demo, !isSyncing, !podID.isEmpty, store.available, !writeTypes.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        _ = await sync(api: api, podID: podID, side: side, days: Self.recentDays)
    }

    /// Rewrites the last `rebuildDays` nights with the current analysis, then deletes everything else
    /// sleepypod ever wrote to Health. Each night is saved before its older samples go, and the final
    /// sweep runs only once every night was handled, so a rebuild that stops partway (pod offline,
    /// phone locked) leaves the earlier data in place instead of emptying Health.
    func rebuild(api: SleepypodProtocol, podID: String, side: Side, demo: Bool) async -> Bool {
        guard enabled, !demo, !isSyncing, !podID.isEmpty, store.available, !writeTypes.isEmpty else { return false }
        isSyncing = true
        rebuildProgress = (0, 0)
        defer { isSyncing = false; rebuildProgress = nil }
        let version = Int(Date().timeIntervalSince1970 * 1000)
        receipts = [:]
        failures = [:]
        persistence.removeObject(forKey: "healthSyncReceipts")
        guard await sync(api: api, podID: podID, side: side, days: Self.rebuildDays) else { return false }
        // Types switched off since an earlier sync may still hold samples; only granted types can be deleted.
        let types = Set(Self.allWriteTypes.filter { store.authorizationStatus(for: $0) == .sharingAuthorized })
        do {
            try await store.deleteAll(types: types, olderThan: version)
            Log.health.info("Rebuilt Health data")
            return true
        } catch {
            authorizationError = error.localizedDescription
            Log.health.error("Health rebuild cleanup failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The core returns at most 30 records per request by default, so long windows are fetched a week at a time,
    /// and a week that hits the cap (fragmented nights) is fetched again a day at a time.
    nonisolated static let recordsPageLimit = 30
    static func sleepRecords(api: SleepypodProtocol, side: Side, start: Date, end: Date, chunk: TimeInterval = 7 * 86400) async throws -> [SleepRecord] {
        var seen = Set<Int>()
        var records: [SleepRecord] = []
        var chunkStart = start
        while chunkStart < end {
            let chunkEnd = min(end, chunkStart.addingTimeInterval(chunk))
            var batch = try await api.getSleepRecords(side: side, start: chunkStart, end: chunkEnd)
            if batch.count >= recordsPageLimit && chunk > 86400 {
                batch = try await sleepRecords(api: api, side: side, start: chunkStart, end: chunkEnd, chunk: 86400)
            }
            for record in batch where seen.insert(record.id).inserted {
                records.append(record)
            }
            chunkStart = chunkEnd
        }
        return records
    }

    /// Returns false if the sync stopped early or any night failed to write, so a rebuild knows not to sweep.
    private func sync(api: SleepypodProtocol, podID: String, side: Side, days: Int) async -> Bool {
        let requestedPreferences = preferences
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        var complete = true
        do {
            let records = try await Self.sleepRecords(api: api, side: side, start: start, end: end).filter {
                $0.side == side.rawValue && $0.enteredBedDate.timeIntervalSince1970 > 0 && $0.leftBedDate > $0.enteredBedDate && $0.leftBedDate <= end
            }
            if rebuildProgress != nil { rebuildProgress = (0, records.count) }
            for record in records {
                if let progress = rebuildProgress { rebuildProgress = (progress.done + 1, progress.total) }
                let key = Self.recordKey(podID: podID, record: record)
                let syncable = Self.isSyncable(record)
                // An excluded record with a receipt was written by an earlier version; only those need cleanup.
                guard syncable ? receipt(podID: podID, record: record) == nil : receipts[key] != nil else { continue }
                do {
                    guard !Task.isCancelled, enabled, preferences == requestedPreferences else { return false }
                    guard writeTypes.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else {
                        failures[key] = "Allow the selected write types in Apple Health."
                        complete = false
                        continue
                    }
                    let deviceID = Self.deviceID(podID: podID, record: record)
                    // Cover the interval an earlier sync wrote too, in case the pod has since moved the record's bounds.
                    let previous = receipts[key]
                    let clearStart = min(record.enteredBedDate, previous?.enteredAt ?? record.enteredBedDate)
                    let clearEnd = max(record.leftBedDate, previous?.closedAt ?? record.leftBedDate)
                    guard syncable else {
                        try await store.delete(types: writeTypes, deviceID: deviceID, start: clearStart, end: clearEnd, olderThan: nil)
                        receipts[key] = nil
                        failures[key] = nil
                        persistence.set(try JSONEncoder().encode(receipts), forKey: "healthSyncReceipts")
                        continue
                    }
                    let vitals = try await api.getVitals(side: side, start: record.enteredBedDate, end: record.leftBedDate)
                    let movement = try await api.getMovement(side: side, start: record.enteredBedDate, end: record.leftBedDate)
                    let calibration = try? await api.getCalibrationStatus(side: side)
                    let analyzer = SleepAnalyzer()
                    analyzer.analyze(vitals: vitals.filter { $0.side == side.rawValue && $0.date >= record.enteredBedDate && $0.date < record.leftBedDate },
                                     movement: movement, calibrationQuality: calibration?.piezo?.qualityScore ?? 0)
                    let filtered = analyzer.filterOutliers(vitals: vitals.filter { $0.side == side.rawValue && $0.date >= record.enteredBedDate && $0.date < record.leftBedDate })
                    guard !Task.isCancelled, enabled, preferences == requestedPreferences else { return false }
                    guard !filtered.isEmpty, !preferences.sleep || !analyzer.stages.isEmpty else {
                        failures[key] = "Waiting for enough vitals to analyze this night."
                        continue
                    }
                    let version = Int(Date().timeIntervalSince1970 * 1000)
                    let samples = Self.samples(record: record, epochs: analyzer.stages, podID: podID, preferences: requestedPreferences,
                                               vitals: filtered, version: version)
                    guard !samples.isEmpty else { continue }
                    try await store.save(samples)
                    // Save first, then drop whatever this write didn't replace, so a failed save never empties the night.
                    try await store.delete(types: writeTypes, deviceID: deviceID, start: clearStart, end: clearEnd, olderThan: version)
                    Log.health.info("Saved \(samples.count, privacy: .private) samples to Health")
                    receipts[key] = Receipt(date: Date(), signature: Self.receiptSignature(requestedPreferences), closedAt: record.leftBedDate, enteredAt: record.enteredBedDate)
                    failures[key] = nil
                    persistence.set(try JSONEncoder().encode(receipts), forKey: "healthSyncReceipts")
                } catch {
                    // A cancelled sync (scene change, backgrounding) retries next time; it isn't a failed night.
                    if Self.isCancellation(error) { return false }
                    failures[key] = error.localizedDescription
                    complete = false
                    Log.health.error("Health sync failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return false }
            authorizationError = error.localizedDescription
            Log.health.error("Health sync fetch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return complete
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case APIError.networkError(let underlying) = error {
            return (underlying as? URLError)?.code == .cancelled || underlying is CancellationError
        }
        return (error as? URLError)?.code == .cancelled
    }

    // Sync identifiers, unlike ExternalUUID alone, make retries idempotent in HealthKit.
    // Incrementing the version permits a corrected record to replace earlier samples.
    static func samples(record: SleepRecord, epochs: [SleepAnalyzer.SleepEpoch], podID: String, preferences: Preferences, vitals: [VitalsRecord]? = nil,
                        version: Int = Int(Date().timeIntervalSince1970 * 1000)) -> [HKSample] {
        guard record.enteredBedDate.timeIntervalSince1970 > 0, record.leftBedDate > record.enteredBedDate else { return [] }
        let key = recordKey(podID: podID, record: record)
        let device = HKDevice(name: "sleepypod", manufacturer: nil, model: "Pod",
                              hardwareVersion: nil, firmwareVersion: nil, softwareVersion: nil,
                              localIdentifier: deviceID(podID: podID, record: record), udiDeviceIdentifier: nil)
        func metadata(_ epoch: String, type: String) -> [String: Any] {
            [HKMetadataKeyExternalUUID: "\(key)-\(epoch)", HKMetadataKeyWasUserEntered: false,
             HKMetadataKeySyncIdentifier: "\(key)-\(epoch)-\(type)", HKMetadataKeySyncVersion: version,
             "sleepypod_side": record.side]
        }
        var result: [HKSample] = []
        if preferences.sleep {
            result.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: record.enteredBedDate, end: record.leftBedDate, device: device, metadata: metadata("inBed", type: "sleep")))
        }
        for epoch in epochs where epoch.start >= record.enteredBedDate && epoch.start < record.leftBedDate {
            let end = min(record.leftBedDate, epoch.start.addingTimeInterval(epoch.duration))
            guard end > epoch.start else { continue }
            let id = String(Int(epoch.start.timeIntervalSince1970))
            if preferences.sleep {
                result.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: stageValue(epoch.stage),
                    start: epoch.start, end: end, device: device, metadata: metadata(id, type: "sleep")))
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
                        start: vital.date, end: end, device: device, metadata: metadata(id, type: type.rawValue)))
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
