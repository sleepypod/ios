import Foundation
import HealthKit

/// A wearable whose readings can sit beside the pod's. Devices differ in what they measure and how, so each says
/// which Health samples are its own and which metrics it reports. Anything it doesn't report simply stays missing.
protocol ReferenceDevice: Sendable {
    /// Metrics beyond heart rate and sleep stages, which every device sends.
    var metrics: [PodWatchUpload.Metric] { get }
    func recorded(_ sample: HKSample) -> Bool
    /// The hardware behind a sample, kept because one metric can change meaning between models.
    func hardware(of sample: HKSample) -> String?
}

struct AppleWatchDevice: ReferenceDevice {
    let metrics = PodWatchUpload.Metric.allCases

    // Only what the Watch itself recorded counts; sleepypod's own writes are never compared against themselves.
    // The source's productType is the usual tell, but some samples carry it only on the device.
    func recorded(_ sample: HKSample) -> Bool {
        guard sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        return sample.sourceRevision.productType?.lowercased().hasPrefix("watch") == true
            || sample.device?.model == "Watch"
            || sample.device?.hardwareVersion?.lowercased().hasPrefix("watch") == true
    }

    func hardware(of sample: HKSample) -> String? {
        [sample.sourceRevision.productType, sample.device?.hardwareVersion].compactMap { $0 }
            .first { $0.lowercased().hasPrefix("watch") }
    }
}

extension ReferenceDevice {
    /// This device's readings of `metric`, in the units the pod stores.
    func samples(_ samples: [HKQuantitySample], of metric: PodWatchUpload.Metric) -> [PodWatchUpload.Sample] {
        samples.filter { recorded($0) && $0.quantity.is(compatibleWith: metric.unit) }.map { sample in
            let start = PodWatchUpload.seconds(sample.startDate), end = PodWatchUpload.seconds(sample.endDate)
            return PodWatchUpload.Sample(timestamp: start, value: sample.quantity.doubleValue(for: metric.unit) * metric.scale,
                                         end: end > start ? end : nil, device: hardware(of: sample),
                                         algorithm: (sample.metadata?[HKMetadataKeyAlgorithmVersion] as? NSNumber)?.stringValue)
        }
    }
}

extension PodWatchUpload.Metric {
    /// Nil on an iOS without the type. The identifier is spelled out so the app still builds with older SDKs.
    var healthType: HKQuantityTypeIdentifier? {
        switch self {
        case .breathingRate: .respiratoryRate
        case .hrvSDNN: .heartRateVariabilitySDNN
        case .hrvRMSSD:
            if #available(iOS 27, *) {
                HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierHeartRateVariabilityRMSSD")
            } else {
                nil
            }
        case .bloodOxygen: .oxygenSaturation
        case .restingHeartRate: .restingHeartRate
        case .skinTemperature: .appleSleepingWristTemperature
        case .breathingDisturbances: .appleSleepingBreathingDisturbances
        }
    }

    var unit: HKUnit {
        switch self {
        case .breathingRate, .restingHeartRate: .count().unitDivided(by: .minute())
        case .hrvSDNN, .hrvRMSSD: .secondUnit(with: .milli)
        case .bloodOxygen: .percent()
        case .skinTemperature: .degreeCelsius()
        case .breathingDisturbances: .count()
        }
    }

    /// Health holds blood oxygen as a fraction; the pod stores a percentage.
    var scale: Double { self == .bloodOxygen ? 100 : 1 }
}
