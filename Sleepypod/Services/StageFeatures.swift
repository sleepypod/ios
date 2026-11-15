import Foundation

/// The inputs a stage model sees, one pure computation shared by training, inference and the parity fixture
/// so the contract cannot drift between them. Epochs are the challenger's 5-minute grid from bed entry.
enum StageFeatures {
    /// Which columns a model was trained on. Stored on its card as `featureContract`.
    enum Contract: String, Codable, Sendable, CaseIterable, Identifiable {
        /// The bundled challenger's four inputs, so a personal fit isolates the domain gap.
        case challenger
        /// Adds what the pod has and a wrist doesn't: HRV, breathing, 15-minute windows.
        case podNative
        /// podNative plus temporal context, movement bouts and arousal features (core's podContext).
        case podContext

        var id: String { rawValue }
        var title: String {
            switch self {
            case .challenger: "Challenger parity"
            case .podNative: "Pod native"
            case .podContext: "Pod context"
            }
        }
        var columns: [String] {
            switch self {
            case .challenger: StageChallenger.Features.columns
            case .podNative: StageChallenger.Features.columns + StageFeatures.podNativeColumns
            case .podContext: Contract.podNative.columns + StageFeatures.podContextColumns
            }
        }

        /// The contract whose columns match a card's list exactly, if any.
        static func matching(_ columns: [String]) -> Contract? {
            allCases.first { $0.columns == columns }
        }
    }

    static let podNativeColumns = ["hrvRel", "hrv15Rel", "hr15StdRel", "br15Std", "motion15", "minutesSinceBed"]
    static let podContextColumns = [
        "hrZPrev", "hrZNext", "hrZMean30", "hrStdZPrev", "hrStdZNext", "hrStdZMean30",
        "motionZPrev", "motionZNext", "motionZMean30", "hrvRelPrev", "hrvRelNext", "hrvRelMean30", "minutesToExit",
        "activeMinutes", "peakMinuteZ", "minutesFromMove", "stillBoutMinutes", "active15",
        "hrRise", "hrMaxZ", "brStdEpoch", "brRel", "moveHrCoupling"
    ]
    /// Half of the 15-minute window, so a window is centred on the epoch midpoint.
    static let windowHalf: TimeInterval = 450

    static func rows(contract: Contract, enteredBed: Date, leftBed: Date, vitals: [VitalsRecord],
                     movement: [MovementRecord]) -> [StageChallenger.FeatureEpoch] {
        let base = StageChallenger.features(enteredBed: enteredBed, leftBed: leftBed, vitals: vitals, movement: movement)
        switch contract {
        case .challenger:
            return base
        case .podNative:
            let extra = podNative(enteredBed: enteredBed, starts: base.map(\.start), vitals: vitals, movement: movement)
            return zip(base, extra).map { epoch, more in
                StageChallenger.FeatureEpoch(start: epoch.start, values: epoch.values.merging(more) { $1 })
            }
        case .podContext:
            let native = rows(contract: .podNative, enteredBed: enteredBed, leftBed: leftBed, vitals: vitals, movement: movement)
            let extra = podContext(enteredBed: enteredBed, leftBed: leftBed, rows: native, vitals: vitals, movement: movement)
            return zip(native, extra).map { epoch, more in
                StageChallenger.FeatureEpoch(start: epoch.start, values: epoch.values.merging(more) { $1 })
            }
        }
    }

    /// Contract B's extra columns for each kept epoch. Ratios are to the night's median (HRV) or std (HR); a
    /// night without a positive denominator gets 0 for the ratio rather than an infinity.
    static func podNative(enteredBed: Date, starts: [Date], vitals: [VitalsRecord], movement: [MovementRecord]) -> [[String: Double]] {
        let sorted = vitals.sorted { $0.date < $1.date }
        let hrv = sorted.compactMap { record in record.hrv.flatMap { $0.isFinite ? (record.date, $0) : nil } }
        let heartRates = sorted.compactMap { record in record.heartRate.flatMap { $0.isFinite ? (record.date, $0) : nil } }
        let breathing = sorted.compactMap { record in record.breathingRate.flatMap { $0.isFinite ? (record.date, $0) : nil } }
        let nightHRVMedian = median(hrv.map(\.1))
        let nightHRStd = StageChallenger.populationStd(heartRates.map(\.1))

        func window<T>(_ samples: [(Date, T)], around mid: Date, half: TimeInterval) -> [T] {
            samples.filter { abs($0.0.timeIntervalSince(mid)) <= half }.map(\.1)
        }
        func ratio(_ value: Double, over denominator: Double) -> Double {
            denominator > 0 && denominator.isFinite ? value / denominator : 0
        }

        return starts.map { start in
            let mid = start.addingTimeInterval(StageChallenger.epochSeconds / 2)
            let epochHRV = window(hrv, around: mid, half: StageChallenger.epochSeconds / 2)
            let hrv15 = window(hrv, around: mid, half: windowHalf)
            let hr15 = window(heartRates, around: mid, half: windowHalf)
            let br15 = window(breathing, around: mid, half: windowHalf)
            let motion15 = movement.filter { abs($0.date.timeIntervalSince(mid)) <= windowHalf }.reduce(0.0) { $0 + Double($1.totalMovement) }
            return [
                "hrvRel": epochHRV.isEmpty ? 0 : ratio(StageChallenger.mean(epochHRV), over: nightHRVMedian),
                "hrv15Rel": hrv15.isEmpty ? 0 : ratio(StageChallenger.mean(hrv15), over: nightHRVMedian),
                "hr15StdRel": hr15.count < 2 ? 0 : ratio(StageChallenger.populationStd(hr15), over: nightHRStd),
                "br15Std": br15.count < 2 ? 0 : StageChallenger.populationStd(br15),
                "motion15": log(1 + motion15),
                "minutesSinceBed": start.timeIntervalSince(enteredBed) / 60
            ]
        }
    }

    /// podContext's extra columns for podNative rows, as core's `stageModelFeatures` computes them on the pod.
    /// Only readings inside [enteredBed, leftBed) count, and movement is taken in time order, because the
    /// still-bout edges fall back to the night's first and last movement minute.
    static func podContext(enteredBed: Date, leftBed: Date, rows: [StageChallenger.FeatureEpoch], vitals: [VitalsRecord],
                           movement: [MovementRecord]) -> [[String: Double]] {
        let epoch = StageChallenger.epochSeconds
        let entered = enteredBed.timeIntervalSince1970
        let left = leftBed.timeIntervalSince1970
        func inBed(_ date: Date) -> Bool { date.timeIntervalSince1970 >= entered && date.timeIntervalSince1970 < left }
        let sorted = vitals.filter { inBed($0.date) }.sorted { $0.date < $1.date }
        let heartRates = sorted.compactMap { record in record.heartRate.flatMap { $0.isFinite ? (record.date.timeIntervalSince1970, $0) : nil } }
        let breathing = sorted.compactMap { record in record.breathingRate.flatMap { $0.isFinite ? (record.date.timeIntervalSince1970, $0) : nil } }
        let moves = movement.filter { inBed($0.date) }.sorted { $0.date < $1.date }
            .map { ($0.date.timeIntervalSince1970, Double($0.totalMovement)) }
        let nightHRStd = StageChallenger.populationStd(heartRates.map(\.1))
        let nightBRMedian = median(breathing.map(\.1))
        let starts = rows.map(\.start.timeIntervalSince1970)
        let byStart = Dictionary(zip(starts, rows), uniquingKeysWith: { first, _ in first })
        func between(_ samples: [(TimeInterval, Double)], _ from: TimeInterval, _ to: TimeInterval) -> [Double] {
            samples.filter { $0.0 >= from && $0.0 < to }.map(\.1)
        }

        // Context: neighbours by time, so a skipped epoch falls back to the epoch's own value.
        var out: [[String: Double]] = rows.enumerated().map { index, row in
            let start = starts[index]
            var values: [String: Double] = ["minutesToExit": (left - start) / 60]
            for column in ["hrZ", "hrStdZ", "motionZ", "hrvRel"] {
                let own = row.values[column] ?? 0
                values[column + "Prev"] = byStart[start - epoch]?.values[column] ?? own
                values[column + "Next"] = byStart[start + epoch]?.values[column] ?? own
                values[column + "Mean30"] = StageChallenger.mean(rows.filter { abs($0.start.timeIntervalSince1970 - start) <= 3 * epoch }
                    .map { $0.values[column] ?? 0 })
            }
            return values
        }

        // Movement: minutes clearly above the night's own floor, and the still bout around each epoch.
        let movementZ = robustZScores(moves.map { log1p($0.1) })
        let active = zip(moves, movementZ).filter { $0.1 > 3 }.map(\.0.0)
        var peaks: [Double] = []
        var hrMax: [Double] = []
        for index in out.indices {
            let start = starts[index]
            let end = start + epoch
            let mid = start + epoch / 2
            let last = active.last { $0 <= mid }
            let next = active.first { $0 > mid }
            let distances = [last, next].compactMap { $0 }.map { abs(mid - $0) }
            let boutStart = last ?? moves.first?.0 ?? start
            let boutEnd = next ?? moves.last?.0 ?? end
            out[index]["activeMinutes"] = Double(active.filter { $0 >= start && $0 < end }.count)
            peaks.append(between(moves, start, end).max().map(log1p) ?? 0)
            out[index]["minutesFromMove"] = distances.min().map { $0 / 60 } ?? 720
            out[index]["stillBoutMinutes"] = max(boutEnd - boutStart, 0) / 60
            out[index]["active15"] = Double(active.filter { abs($0 - mid) <= 900 }.count)

            // Arousal: heart-rate rise against the preceding 15 minutes, breathing within the epoch.
            let beats = between(heartRates, start, end)
            let prior = between(heartRates, start - 900, start)
            let breaths = between(breathing, start, end)
            out[index]["hrRise"] = !beats.isEmpty && !prior.isEmpty && nightHRStd > 0 ? ((beats.max() ?? 0) - median(prior)) / nightHRStd : 0
            hrMax.append(beats.max() ?? -.infinity)
            out[index]["brStdEpoch"] = breaths.count > 1 ? StageChallenger.populationStd(breaths) : 0
            out[index]["brRel"] = !breaths.isEmpty && nightBRMedian > 0 ? StageChallenger.mean(breaths) / nightBRMedian : 0
        }
        let peakZ = robustZScores(peaks)
        let hrMaxZ = StageChallenger.zScores(hrMax)
        for index in out.indices {
            out[index]["peakMinuteZ"] = peakZ[index]
            out[index]["hrMaxZ"] = hrMaxZ[index]
            out[index]["moveHrCoupling"] = (out[index]["activeMinutes"] ?? 0) * max(out[index]["hrRise"] ?? 0, 0)
        }
        return out
    }

    /// Median-centred, scaled by 1.4826 × MAD; all zeros when the MAD is zero.
    static func robustZScores(_ values: [Double]) -> [Double] {
        let center = median(values)
        let mad = median(values.map { abs($0 - center) }) * 1.4826
        return values.map { mad > 0 ? ($0 - center) / mad : 0 }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
    }
}
