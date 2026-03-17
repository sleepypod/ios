import Foundation
import CoreML
import Observation

/// On-device sleep analysis using Core ML.
///
/// Pipeline:
/// 1. Fetch raw vitals (HR, HRV, breathing) from the pod
/// 2. Preprocess: filter outliers, normalize, window into epochs
/// 3. Classify each epoch into a sleep stage (wake/light/deep/REM)
/// 4. Compute sleep quality score from stage distribution
///
/// The model expects 30-second epochs with features:
///   [heartRate, hrv, breathingRate, hrDelta, hrvDelta, brDelta]
///
/// Until a trained model is available, we use rule-based heuristics
/// derived from published thresholds (see docs/health-vitals-science.md).
@MainActor
@Observable
final class SleepAnalyzer {

    var stages: [SleepEpoch] = []
    var qualityScore: Int?
    var isAnalyzing = false

    // MARK: - Types

    enum SleepStage: String, Sendable {
        case wake = "Wake"
        case light = "Light"
        case deep = "Deep"
        case rem = "REM"

        var color: String {
            switch self {
            case .wake: "888888"
            case .light: "4a90d9"
            case .deep: "2563eb"
            case .rem: "a080d0"
            }
        }
    }

    struct SleepEpoch: Identifiable, Sendable {
        let id = UUID()
        let start: Date
        let duration: TimeInterval  // typically 30s or 60s
        let stage: SleepStage
        let heartRate: Double
        let hrv: Double?
        let breathingRate: Double?
    }

    // MARK: - Analyze

    /// Analyze vitals records and classify sleep stages.
    /// Uses rule-based heuristics until a Core ML model is trained.
    ///
    /// - Parameters:
    ///   - vitals: Raw vitals records from the pod.
    ///   - movement: Movement records from the same time window.
    ///   - calibrationQuality: Piezo calibration quality (0.0-1.0). Values below 0.3
    ///     trigger movement-only classification mode since HR/HRV are unreliable.
    func analyze(vitals: [VitalsRecord], movement: [MovementRecord] = [], calibrationQuality: Double = 1.0) {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Filter outliers with tighter sleep-context thresholds
        let filtered = filterOutliers(vitals: vitals)

        let sorted = filtered.sorted { $0.date < $1.date }

        guard sorted.count >= 5 else {
            stages = []
            qualityScore = nil
            return
        }

        // Build a movement lookup keyed by timestamp (rounded to nearest minute)
        let movementByMinute = buildMovementLookup(movement)

        // Classify each record as an epoch
        let avgHR = sorted.compactMap(\.heartRate).reduce(0, +) / Double(sorted.compactMap(\.heartRate).count)

        var classified = sorted.map { record -> SleepEpoch in
            let hr = record.heartRate ?? avgHR
            let hrv = record.hrv
            let br = record.breathingRate
            let mov = lookupMovement(for: record.date, in: movementByMinute)

            let stage = classifyEpoch(
                hr: hr, hrv: hrv, br: br, avgHR: avgHR,
                movement: mov, calibrationQuality: calibrationQuality
            )

            let duration: TimeInterval = 60

            return SleepEpoch(
                start: record.date,
                duration: duration,
                stage: stage,
                heartRate: hr,
                hrv: hrv,
                breathingRate: br
            )
        }

        // Post-processing passes
        applyTemporalSmoothing(&classified)
        applyTransitionConstraints(&classified)

        stages = classified
        qualityScore = computeQualityScore(calibrationQuality: calibrationQuality)
        Log.general.info("Sleep analysis: \(self.stages.count) epochs, score=\(self.qualityScore ?? 0)")
    }

    // MARK: - Outlier Filtering

    /// Filter vitals with sleep-context thresholds.
    /// - HR 45-130 BPM (40 BPM is almost always a BCG half-harmonic)
    /// - HRV > 0 and <= 300
    /// - BR 8-25 bpm (values outside are artifacts)
    /// - Windowed median filter: reject HR > 2 SD from 5-minute rolling median
    private func filterOutliers(vitals: [VitalsRecord]) -> [VitalsRecord] {
        // First pass: hard physiological limits for sleep context
        var filtered = vitals.filter { r in
            if let hr = r.heartRate, (hr < 45 || hr > 130) { return false }
            if let hrv = r.hrv, hrv > 300 { return false }
            if let br = r.breathingRate, (br < 8 || br > 25) { return false }
            return r.heartRate != nil  // must have HR
        }

        // Sort for windowed filter
        filtered.sort { $0.date < $1.date }

        // Second pass: windowed median filter for HR
        // Reject readings > 2 SD from a 5-minute rolling median
        guard filtered.count > 5 else { return filtered }

        let windowSeconds: TimeInterval = 300  // 5 minutes
        var result: [VitalsRecord] = []

        for (i, record) in filtered.enumerated() {
            guard let hr = record.heartRate else {
                result.append(record)
                continue
            }

            // Collect HR values within the 5-minute window centered on this record
            var windowHRs: [Double] = []
            for j in 0..<filtered.count {
                guard let otherHR = filtered[j].heartRate else { continue }
                let dt = abs(filtered[j].date.timeIntervalSince(record.date))
                if dt <= windowSeconds / 2 {
                    windowHRs.append(otherHR)
                }
                // Early exit: if we've passed the window, stop scanning forward
                if j > i && filtered[j].date.timeIntervalSince(record.date) > windowSeconds / 2 {
                    break
                }
            }

            guard windowHRs.count >= 3 else {
                result.append(record)
                continue
            }

            let sortedWindow = windowHRs.sorted()
            let median = sortedWindow[sortedWindow.count / 2]
            let mean = windowHRs.reduce(0, +) / Double(windowHRs.count)
            let variance = windowHRs.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(windowHRs.count)
            let sd = sqrt(variance)

            // Reject if > 2 SD from median (and SD is meaningful)
            if sd > 1.0 && abs(hr - median) > 2 * sd {
                continue  // skip this outlier
            }

            result.append(record)
        }

        return result
    }

    // MARK: - Movement Lookup

    /// Build a dictionary mapping minute-rounded timestamps to movement values.
    private func buildMovementLookup(_ records: [MovementRecord]) -> [Int: Int] {
        var lookup: [Int: Int] = [:]
        for record in records {
            // Round to nearest minute
            let minuteKey = record.timestamp / 60
            lookup[minuteKey] = record.totalMovement
        }
        return lookup
    }

    /// Find the closest movement value for a given date.
    private func lookupMovement(for date: Date, in lookup: [Int: Int]) -> Int? {
        guard !lookup.isEmpty else { return nil }
        let minuteKey = Int(date.timeIntervalSince1970) / 60
        // Check exact minute and neighbors (+/- 1 minute)
        if let exact = lookup[minuteKey] { return exact }
        if let prev = lookup[minuteKey - 1] { return prev }
        if let next = lookup[minuteKey + 1] { return next }
        return nil
    }

    // MARK: - Rule-Based Classification
    //
    // Decision tree (priority order):
    //
    // 1. Calibration check — if calibrationQuality < 0.3, movement-only mode
    // 2. Wake detection (movement-first) — movement > 200 → Wake
    // 3. Deep sleep — hrRatio < 0.92
    // 4. REM detection — hrRatio >= 0.95 AND hrv < 25 AND movement < 30
    // 5. High HR without movement → REM
    // 6. High HR with movement → Wake
    // 7. Default → Light
    //
    // Null HRV handling:
    //   - Null HRV + high movement → Wake
    //   - Null HRV + low movement + low HR → Deep
    //   - Null HRV + low movement + normal HR → Light (NEVER default to REM)

    private func classifyEpoch(
        hr: Double, hrv: Double?, br: Double?, avgHR: Double,
        movement: Int?, calibrationQuality: Double
    ) -> SleepStage {
        let hrRatio = hr / avgHR
        let mov = movement ?? 0

        // 1. Calibration check — unreliable HR, use movement only
        if calibrationQuality < 0.3 {
            if mov > 300 { return .wake }
            if mov > 100 { return .light }
            return .light  // No Deep/REM distinction possible without reliable HR
        }

        // 2. Wake detection (movement-first)
        // Movement > 400 is unconditional wake
        if mov > 400 { return .wake }
        if mov > 200 { return .wake }

        // 3. Deep sleep — HR well below average
        if hrRatio < 0.92 {
            return .deep
        }

        // 4. REM detection — requires positive evidence
        if hrRatio >= 0.95, let hrv, hrv < 25, mov < 30 {
            return .rem
        }

        // 5. High HR without movement → REM (HR surges during REM without body movement)
        if hrRatio > 1.10 && mov < 30 {
            return .rem
        }

        // 6. High HR with movement → Wake
        if hrRatio > 1.10 && mov >= 30 {
            return .wake
        }

        // Null HRV handling
        if hrv == nil {
            if mov > 100 { return .wake }
            // Low HR + no movement = likely deep (already caught by hrRatio < 0.92 above)
            // Normal HR + no movement = Light
            return .light
        }

        // 7. Default → Light (critical fix: was returning .rem before)
        return .light
    }

    // MARK: - Temporal Smoothing
    //
    // Replace isolated single-epoch stages: if an epoch's stage differs from both
    // neighbors, replace it with the previous neighbor's stage. This removes noise
    // from single-epoch misclassifications.

    private func applyTemporalSmoothing(_ epochs: inout [SleepEpoch]) {
        guard epochs.count >= 3 else { return }

        for i in 1..<(epochs.count - 1) {
            if epochs[i].stage != epochs[i - 1].stage && epochs[i].stage != epochs[i + 1].stage {
                let original = epochs[i]
                epochs[i] = SleepEpoch(
                    start: original.start,
                    duration: original.duration,
                    stage: epochs[i - 1].stage,
                    heartRate: original.heartRate,
                    hrv: original.hrv,
                    breathingRate: original.breathingRate
                )
            }
        }
    }

    // MARK: - Transition Constraints
    //
    // Enforce physiological transition rules:
    //   - Wake → Deep must pass through Light
    //   - Deep → REM must pass through Light
    //   - REM → Deep must pass through Light
    // If a transition violates these, insert Light.

    private func applyTransitionConstraints(_ epochs: inout [SleepEpoch]) {
        guard epochs.count >= 2 else { return }

        var i = 1
        while i < epochs.count {
            let prev = epochs[i - 1].stage
            let curr = epochs[i].stage

            let needsLight =
                (prev == .wake && curr == .deep) ||
                (prev == .deep && curr == .rem) ||
                (prev == .rem && curr == .deep)

            if needsLight {
                let original = epochs[i]
                let lightEpoch = SleepEpoch(
                    start: original.start,
                    duration: original.duration,
                    stage: .light,
                    heartRate: original.heartRate,
                    hrv: original.hrv,
                    breathingRate: original.breathingRate
                )
                epochs[i] = lightEpoch
                // Don't advance — re-check the same position on next iteration
                // since we changed it to Light, the next transition needs checking too
            }
            i += 1
        }
    }

    // MARK: - Quality Score
    //
    // Based on sleep stage distribution targets from Walker, "Why We Sleep" (2017):
    //   - Deep sleep: ~20% of total (critical for physical recovery)
    //   - REM: ~25% of total (critical for memory consolidation)
    //   - Light: ~50% (normal)
    //   - Wake: <5% (interruptions)
    //
    // Score = 100 - penalties for deviation from targets

    private func computeQualityScore(calibrationQuality: Double = 1.0) -> Int {
        guard !stages.isEmpty else { return 0 }

        let total = Double(stages.count)
        let deepPct = Double(stages.filter { $0.stage == .deep }.count) / total * 100
        let remPct = Double(stages.filter { $0.stage == .rem }.count) / total * 100
        let wakePct = Double(stages.filter { $0.stage == .wake }.count) / total * 100

        var score = 100

        // Penalize insufficient deep sleep (target: 15-25%)
        if deepPct < 15 { score -= Int((15 - deepPct) * 2) }
        if deepPct > 30 { score -= Int((deepPct - 30)) }

        // Penalize insufficient REM (target: 20-30%)
        if remPct < 20 { score -= Int((20 - remPct) * 1.5) }
        if remPct > 35 { score -= Int((remPct - 35)) }

        // Penalize wake time (target: <5%)
        if wakePct > 5 { score -= Int((wakePct - 5) * 3) }

        score = max(0, min(100, score))

        // Cap score at 50 if calibration is poor
        if calibrationQuality < 0.3 {
            score = min(score, 50)
        }

        return score
    }

    // MARK: - Core ML (Future)

    /// Load and run a trained Core ML model for sleep stage classification.
    /// Expected model input: MLMultiArray with shape [epochs, 6]
    ///   Features per epoch: [hr, hrv, br, hr_delta, hrv_delta, br_delta]
    /// Expected output: MLMultiArray with shape [epochs] containing stage indices
    ///   0=wake, 1=light, 2=deep, 3=rem
    ///
    /// To train a model:
    /// 1. Collect labeled sleep data (polysomnography or validated wearable)
    /// 2. Extract features per 30s epoch
    /// 3. Train a 1D-CNN or LSTM in Create ML / PyTorch
    /// 4. Convert to .mlmodel and add to Xcode project
    ///
    /// func analyzeWithModel(vitals: [VitalsRecord]) throws {
    ///     let model = try SleepStageClassifier(configuration: .init())
    ///     let input = prepareModelInput(vitals)
    ///     let output = try model.prediction(input: input)
    ///     stages = parseModelOutput(output, vitals: vitals)
    /// }
}
