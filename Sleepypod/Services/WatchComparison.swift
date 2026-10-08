import Foundation

/// One night of the pod's analysis set against an Apple Watch worn on the same side.
/// Pure value work on plain readings, so it runs without a Health store in tests and demo.
struct WatchComparison: Sendable {
    struct StageSample: Sendable, Equatable {
        let start: Date
        let end: Date
        let stage: SleepAnalyzer.SleepStage
    }
    struct Reading: Sendable, Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }
    struct Disagreement: Identifiable, Sendable, Equatable {
        let ours: SleepAnalyzer.SleepStage
        let watch: SleepAnalyzer.SleepStage
        let seconds: TimeInterval
        var id: String { "\(ours.rawValue)-\(watch.rawValue)" }
    }
    struct StageAgreement: Sendable {
        let comparedSeconds: TimeInterval
        let matchedSeconds: TimeInterval
        let disagreements: [Disagreement]
        var percent: Double? { comparedSeconds > 0 ? matchedSeconds / comparedSeconds * 100 : nil }
    }
    struct HeartRatePair: Identifiable, Sendable {
        var id: Date { date }
        let date: Date
        let ours: Double
        let watch: Double
    }
    struct Averages: Sendable {
        let ours: Double?
        let watch: Double?
        var difference: Double? {
            guard let ours, let watch else { return nil }
            return ours - watch
        }
    }

    let watchStages: [StageSample]
    let stages: StageAgreement
    let heartRate: [HeartRatePair]
    let watchHeartRate: [Reading]
    let hrv: Averages
    let breathing: Averages

    var hasWatchData: Bool { !watchStages.isEmpty || !watchHeartRate.isEmpty || hrv.watch != nil || breathing.watch != nil }
    /// Mean absolute error in bpm over the matched minutes.
    var heartRateError: Double? {
        heartRate.isEmpty ? nil : heartRate.map { abs($0.ours - $0.watch) }.reduce(0, +) / Double(heartRate.count)
    }
    /// Positive when the pod reads higher than the Watch.
    var heartRateBias: Double? {
        heartRate.isEmpty ? nil : heartRate.map { $0.ours - $0.watch }.reduce(0, +) / Double(heartRate.count)
    }

    static func build(epochs: [SleepAnalyzer.SleepEpoch], vitals: [VitalsRecord], watchStages: [StageSample],
                      watchHeartRate: [Reading], watchHRV: [Reading], watchBreathing: [Reading],
                      heartRateTolerance: TimeInterval = 90) -> WatchComparison {
        WatchComparison(
            watchStages: watchStages.sorted { $0.start < $1.start },
            stages: stageAgreement(epochs: epochs, watch: watchStages),
            heartRate: heartRatePairs(vitals: vitals, watch: watchHeartRate, tolerance: heartRateTolerance),
            watchHeartRate: watchHeartRate.sorted { $0.date < $1.date },
            hrv: Averages(ours: mean(vitals.compactMap(\.hrv)), watch: mean(watchHRV.map(\.value))),
            breathing: Averages(ours: mean(vitals.compactMap(\.breathingRate)), watch: mean(watchBreathing.map(\.value))))
    }

    /// Minute-by-minute: an epoch counts only when the Watch recorded exactly one stage at its midpoint.
    static func stageAgreement(epochs: [SleepAnalyzer.SleepEpoch], watch: [StageSample]) -> StageAgreement {
        var compared: TimeInterval = 0, matched: TimeInterval = 0
        var mismatches: [String: Disagreement] = [:]
        for epoch in epochs {
            let midpoint = epoch.start.addingTimeInterval(epoch.duration / 2)
            let stages = Set(watch.filter { $0.start <= midpoint && $0.end > midpoint }.map(\.stage))
            guard stages.count == 1, let theirs = stages.first else { continue }
            compared += epoch.duration
            if theirs == epoch.stage {
                matched += epoch.duration
            } else {
                let key = "\(epoch.stage.rawValue)-\(theirs.rawValue)"
                let seconds = (mismatches[key]?.seconds ?? 0) + epoch.duration
                mismatches[key] = Disagreement(ours: epoch.stage, watch: theirs, seconds: seconds)
            }
        }
        let disagreements = mismatches.values.sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }
        return StageAgreement(comparedSeconds: compared, matchedSeconds: matched, disagreements: disagreements)
    }

    /// Each Watch reading pairs with the pod reading nearest in time, if one lies within the tolerance.
    static func heartRatePairs(vitals: [VitalsRecord], watch: [Reading], tolerance: TimeInterval) -> [HeartRatePair] {
        let ours = vitals.compactMap { record in record.heartRate.map { Reading(date: record.date, value: $0) } }
            .sorted { $0.date < $1.date }
        guard !ours.isEmpty else { return [] }
        return watch.sorted { $0.date < $1.date }.compactMap { reading in
            let nearest = ours.min { abs($0.date.timeIntervalSince(reading.date)) < abs($1.date.timeIntervalSince(reading.date)) }
            guard let nearest, abs(nearest.date.timeIntervalSince(reading.date)) <= tolerance else { return nil }
            return HeartRatePair(date: reading.date, ours: nearest.value, watch: reading.value)
        }
    }

    /// Adjacent samples of one stage collapse into a single block for drawing.
    static func merged(_ samples: [StageSample], maxGap: TimeInterval = 300) -> [StageSample] {
        var result: [StageSample] = []
        for sample in samples.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, last.stage == sample.stage, sample.start.timeIntervalSince(last.end) <= maxGap {
                result[result.count - 1] = StageSample(start: last.start, end: max(last.end, sample.end), stage: last.stage)
            } else {
                result.append(sample)
            }
        }
        return result
    }

    static func mean(_ values: [Double]) -> Double? {
        let finite = values.filter(\.isFinite)
        return finite.isEmpty ? nil : finite.reduce(0, +) / Double(finite.count)
    }

    // MARK: Demo

    /// Deterministic stand-in for a Watch when no pod is connected, so the page can be seen and captured.
    static func demo(record: SleepRecord, epochs: [SleepAnalyzer.SleepEpoch], vitals: [VitalsRecord]) -> WatchComparison {
        var seed = UInt64(truncatingIfNeeded: record.id &* 2_654_435_761) | 1
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        let sorted = epochs.sorted { $0.start < $1.start }
        // The Watch tends to call sleep onset a little later and swaps the odd stage for a neighbour.
        var stages: [StageSample] = []
        let kept = Array(sorted.dropFirst(min(8, sorted.count / 8)))
        for (index, epoch) in kept.enumerated() {
            let roll = next()
            let stage: SleepAnalyzer.SleepStage = switch epoch.stage {
            case .light: roll < 0.12 ? .deep : roll < 0.18 ? .rem : .light
            case .deep: roll < 0.14 ? .light : .deep
            case .rem: roll < 0.10 ? .light : .rem
            case .wake: roll < 0.20 ? .light : .wake
            }
            // A real Watch writes back-to-back samples, so each one runs until the next begins.
            let end = index + 1 < kept.count ? kept[index + 1].start : epoch.start.addingTimeInterval(epoch.duration)
            stages.append(StageSample(start: epoch.start, end: end, stage: stage))
        }
        let readings = vitals.sorted { $0.date < $1.date }
        var heartRate: [Reading] = []
        for (index, vital) in readings.enumerated() where index % 2 == 0 {
            guard let hr = vital.heartRate else { continue }
            heartRate.append(Reading(date: vital.date.addingTimeInterval(20), value: (hr + 1 + (next() - 0.5) * 5).rounded()))
        }
        let hrvValues = readings.compactMap(\.hrv)
        let hrv = stride(from: 0, to: hrvValues.count, by: max(1, hrvValues.count / 4)).map {
            Reading(date: readings[$0].date, value: hrvValues[$0] * (1.08 + (next() - 0.5) * 0.2))
        }
        let breathing = mean(readings.compactMap(\.breathingRate)).map { [Reading(date: record.enteredBedDate, value: $0 + 0.3)] } ?? []
        return build(epochs: epochs, vitals: vitals, watchStages: stages, watchHeartRate: heartRate, watchHRV: hrv, watchBreathing: breathing)
    }
}
