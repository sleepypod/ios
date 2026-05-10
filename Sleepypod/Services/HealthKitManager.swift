import Foundation
import HealthKit
import Observation

/// Writes Sleepypod-derived sleep + vitals to Apple Health.
///
/// Idempotency: every sample carries `HKMetadataKeySyncIdentifier` keyed by
/// the source record id, so re-syncing the same week replaces prior writes
/// instead of duplicating. The Sleepypod app is the single source for these
/// samples in the user's Health store.
@MainActor
@Observable
final class HealthKitManager {
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorizationRequested = false
    var lastSyncedAt: Date?
    var lastSyncedSamples = 0
    var error: String?

    private let store = HKHealthStore()

    private static let syncVersion: Int = 1

    private static let writeTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = []
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .respiratoryRate) { types.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(t) }
        return types
    }()

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else {
            Log.health.info("HealthKit unavailable on this device")
            return
        }
        do {
            try await store.requestAuthorization(toShare: Self.writeTypes, read: [])
            authorizationRequested = true
        } catch {
            self.error = error.localizedDescription
            Log.health.error("authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sync

    /// Writes sleep + vitals to Health. Safe to call repeatedly — replaces
    /// prior samples with matching sync identifiers.
    func sync(side: Side, sleep: [SleepRecord], vitals: [VitalsRecord]) async {
        guard isAvailable else { return }

        var samples: [HKSample] = []
        samples.append(contentsOf: sleepSamples(records: sleep, side: side))
        samples.append(contentsOf: vitalsSamples(records: vitals, side: side))

        guard !samples.isEmpty else { return }

        do {
            try await store.save(samples)
            lastSyncedAt = .now
            lastSyncedSamples = samples.count
            error = nil
            Log.health.info("synced \(samples.count) samples (side=\(side.rawValue, privacy: .public))")
        } catch {
            self.error = error.localizedDescription
            Log.health.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sample builders

    private func sleepSamples(records: [SleepRecord], side: Side) -> [HKSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let device = sleepypodDevice(side: side)
        var out: [HKSample] = []

        for record in records {
            let inBedStart = record.enteredBedDate
            let inBedEnd = record.leftBedDate
            guard inBedEnd > inBedStart else { continue }

            // In-bed interval — covers the full session window
            out.append(HKCategorySample(
                type: type,
                value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: inBedStart,
                end: inBedEnd,
                device: device,
                metadata: metadata(syncId: "sleepypod-inbed-\(side.rawValue)-\(record.id)", side: side)
            ))

            // Asleep interval — duration from sleepPeriodSeconds, anchored to bed entry.
            // We don't have stage-level breakdown, so emit asleepUnspecified.
            let asleepSeconds = TimeInterval(record.sleepPeriodSeconds)
            if asleepSeconds > 0 {
                let asleepEnd = min(inBedStart.addingTimeInterval(asleepSeconds), inBedEnd)
                out.append(HKCategorySample(
                    type: type,
                    value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    start: inBedStart,
                    end: asleepEnd,
                    device: device,
                    metadata: metadata(syncId: "sleepypod-asleep-\(side.rawValue)-\(record.id)", side: side)
                ))
            }
        }
        return out
    }

    private func vitalsSamples(records: [VitalsRecord], side: Side) -> [HKSample] {
        let bpm = HKUnit(from: "count/min")
        let ms = HKUnit.secondUnit(with: .milli)
        let device = sleepypodDevice(side: side)
        var out: [HKSample] = []

        for record in records {
            let date = record.date
            guard date.timeIntervalSince1970 > 0 else { continue }

            if let hr = record.heartRate, hr > 0,
               let type = HKObjectType.quantityType(forIdentifier: .heartRate) {
                out.append(HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: bpm, doubleValue: hr),
                    start: date,
                    end: date,
                    device: device,
                    metadata: metadata(syncId: "sleepypod-hr-\(side.rawValue)-\(record.id)", side: side)
                ))
            }

            if let br = record.breathingRate, br > 0,
               let type = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
                out.append(HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: bpm, doubleValue: br),
                    start: date,
                    end: date,
                    device: device,
                    metadata: metadata(syncId: "sleepypod-br-\(side.rawValue)-\(record.id)", side: side)
                ))
            }

            if let hrv = record.hrv, hrv > 0,
               let type = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
                out.append(HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: ms, doubleValue: hrv),
                    start: date,
                    end: date,
                    device: device,
                    metadata: metadata(syncId: "sleepypod-hrv-\(side.rawValue)-\(record.id)", side: side)
                ))
            }
        }
        return out
    }

    // MARK: - Helpers

    private func metadata(syncId: String, side: Side) -> [String: Any] {
        [
            HKMetadataKeySyncIdentifier: syncId,
            HKMetadataKeySyncVersion: Self.syncVersion,
            HKMetadataKeyExternalUUID: syncId,
            "sleepypod_side": side.rawValue,
        ]
    }

    private func sleepypodDevice(side: Side) -> HKDevice {
        HKDevice(
            name: "Sleepypod",
            manufacturer: "Sleepypod",
            model: "Pod",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: side.rawValue,
            udiDeviceIdentifier: nil
        )
    }
}
