import Foundation

/// Simulates adaptive temperature recommendations by replaying vitals data.
/// Used for testing and shadow mode validation — no hardware changes.
struct AdaptiveSimulator: Sendable {

    struct Recommendation: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let currentTemp: Int
        let recommendedTemp: Int
        let reason: String
        let confidence: Double
        let sleepStage: SleepAnalyzer.SleepStage?
        let heartRate: Double?
        let movement: Int?
    }

    struct Config: Sendable {
        var initialTemp: Int = 78
        var minTemp: Int = 65
        var maxTemp: Int = 90
        var adjustmentIntervalMinutes: Int = 5
        var maxChangePerInterval: Int = 2  // Max °F change per interval
        var movementWakeThreshold: Int = 200
        var deepSleepHRRatio: Double = 0.92
        var calibrationQuality: Double = 1.0
    }

    /// Replay vitals + movement through the adaptive engine.
    /// Returns a sequence of temperature recommendations.
    static func simulate(
        vitals: [VitalsRecord],
        movement: [MovementRecord],
        config: Config = Config()
    ) -> [Recommendation] {
        let sorted = vitals.filter { $0.heartRate != nil }.sorted { $0.date < $1.date }
        guard sorted.count >= 5 else { return [] }

        let avgHR = sorted.compactMap(\.heartRate).reduce(0, +) / Double(sorted.compactMap(\.heartRate).count)

        // Build movement lookup
        var movementByMinute: [Int: Int] = [:]
        for m in movement {
            let minute = Int(m.date.timeIntervalSince1970) / 60
            movementByMinute[minute] = m.totalMovement
        }

        var recommendations: [Recommendation] = []
        var currentTemp = config.initialTemp
        var lastAdjustment: Date = .distantPast

        for record in sorted {
            let elapsed = record.date.timeIntervalSince(lastAdjustment)
            guard elapsed >= Double(config.adjustmentIntervalMinutes) * 60 else { continue }

            let hr = record.heartRate ?? avgHR
            let hrv = record.hrv
            let hrRatio = hr / avgHR
            let minute = Int(record.date.timeIntervalSince1970) / 60
            let mov = movementByMinute[minute] ?? 0

            // Classify current state
            let stage = classifyStage(hrRatio: hrRatio, hrv: hrv, movement: mov, calibrationQuality: config.calibrationQuality)

            // Determine recommendation
            let (delta, reason) = recommendDelta(
                stage: stage,
                hrRatio: hrRatio,
                movement: mov,
                currentTemp: currentTemp,
                config: config
            )

            let newTemp = max(config.minTemp, min(config.maxTemp, currentTemp + delta))

            if newTemp != currentTemp {
                let confidence = computeConfidence(
                    stage: stage,
                    calibrationQuality: config.calibrationQuality,
                    hrv: hrv
                )

                recommendations.append(Recommendation(
                    timestamp: record.date,
                    currentTemp: currentTemp,
                    recommendedTemp: newTemp,
                    reason: reason,
                    confidence: confidence,
                    sleepStage: stage,
                    heartRate: hr,
                    movement: mov
                ))

                currentTemp = newTemp
                lastAdjustment = record.date
            }
        }

        return recommendations
    }

    // MARK: - Classification

    private static func classifyStage(
        hrRatio: Double, hrv: Double?, movement: Int, calibrationQuality: Double
    ) -> SleepAnalyzer.SleepStage {
        if calibrationQuality < 0.3 {
            return movement > 200 ? .wake : .light
        }
        if movement > 200 { return .wake }
        if hrRatio < 0.92 { return .deep }
        if hrRatio >= 0.95, let hrv, hrv < 25, movement < 30 { return .rem }
        return .light
    }

    // MARK: - Recommendation

    private static func recommendDelta(
        stage: SleepAnalyzer.SleepStage,
        hrRatio: Double,
        movement: Int,
        currentTemp: Int,
        config: Config
    ) -> (Int, String) {
        switch stage {
        case .deep:
            // Cool further if not at min
            if currentTemp > config.minTemp + 2 {
                return (-min(config.maxChangePerInterval, currentTemp - config.minTemp), "deep_sleep_cooling")
            }
            return (0, "deep_sleep_at_min")

        case .wake:
            // Pause changes during wake
            return (0, "wake_detected_pause")

        case .rem:
            // Slight warming during REM (body temp regulation is impaired)
            if currentTemp < config.maxTemp - 5 {
                return (1, "rem_warming")
            }
            return (0, "rem_at_target")

        case .light:
            // Gradual transition — move toward midpoint
            let midpoint = (config.minTemp + config.maxTemp) / 2
            if currentTemp < midpoint - 2 {
                return (1, "light_sleep_warming")
            } else if currentTemp > midpoint + 2 {
                return (-1, "light_sleep_cooling")
            }
            return (0, "light_sleep_stable")
        }
    }

    // MARK: - Confidence

    private static func computeConfidence(
        stage: SleepAnalyzer.SleepStage,
        calibrationQuality: Double,
        hrv: Double?
    ) -> Double {
        var confidence = calibrationQuality

        // Higher confidence for deep sleep (clear HR signal)
        if stage == .deep { confidence *= 1.2 }

        // Lower confidence without HRV
        if hrv == nil { confidence *= 0.6 }

        // Wake is always high confidence (movement-based)
        if stage == .wake { confidence = max(confidence, 0.8) }

        return min(1.0, confidence)
    }
}
