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
    func analyze(vitals: [VitalsRecord]) {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Filter and sort
        let sorted = vitals
            .filter { r in
                guard let hr = r.heartRate, hr > 30, hr < 200 else { return false }
                return true
            }
            .sorted { $0.date < $1.date }

        guard sorted.count >= 5 else {
            stages = []
            qualityScore = nil
            return
        }

        // Classify each record as an epoch
        let avgHR = sorted.compactMap(\.heartRate).reduce(0, +) / Double(sorted.compactMap(\.heartRate).count)

        stages = sorted.map { record in
            let hr = record.heartRate ?? avgHR
            let hrv = record.hrv
            let br = record.breathingRate

            let stage = classifyEpoch(hr: hr, hrv: hrv, br: br, avgHR: avgHR)

            // Estimate epoch duration from gap to next record (capped at 5 min)
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

        qualityScore = computeQualityScore()
        Log.general.info("Sleep analysis: \(self.stages.count) epochs, score=\(self.qualityScore ?? 0)")
    }

    // MARK: - Rule-Based Classification
    //
    // Thresholds from:
    //   - Fonseca et al., "Cardiorespiratory sleep stage classification," 2018
    //   - Walch et al., "Sleep stage prediction with raw acceleration and PPG," PNAS 2019
    //
    // HR < 85% of avg + HRV high → Deep sleep
    // HR > 95% of avg + HRV low + BR irregular → REM
    // HR > avg + movement → Wake
    // Otherwise → Light sleep

    private func classifyEpoch(hr: Double, hrv: Double?, br: Double?, avgHR: Double) -> SleepStage {
        let hrRatio = hr / avgHR

        // Deep sleep: low HR, high HRV
        if hrRatio < 0.85 {
            if let hrv, hrv > 40 {
                return .deep
            }
            return .deep // Low HR alone suggests deep sleep
        }

        // REM: HR similar to wake, HRV drops, breathing may be irregular
        if hrRatio > 0.95 {
            if let hrv, hrv < 30 {
                return .rem
            }
            if hrRatio > 1.1 {
                return .wake
            }
            return .rem
        }

        // Default: light sleep
        return .light
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

    private func computeQualityScore() -> Int {
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

        return max(0, min(100, score))
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
