import Foundation

/// Generates a science-backed temperature curve from bedtime and wake time.
///
/// References:
/// - Heller 2012: warming before bed dilates blood vessels, accelerates core heat loss
/// - Kräuchi 2007: core body temp drop of 1-2°F triggers sleep onset
/// - Czeisler 1999: rising body temp 30min before wake triggers natural waking
/// - Walker 2017: sleep quality correlates with thermal environment
struct SleepCurve {

    /// A point on the temperature curve
    struct Point: Identifiable, Sendable {
        let id = UUID()
        let time: Date
        let tempOffset: Int  // relative to base (80°F), e.g. -6 = 74°F
        let phase: Phase
    }

    enum Phase: String, Sendable {
        case warmUp = "Wind Down"
        case coolDown = "Fall Asleep"
        case deepSleep = "Deep Sleep"
        case maintain = "Maintain"
        case preWake = "Pre-Wake"
        case wake = "Wake"
    }

    /// Generate a temperature curve from bedtime and wake time.
    /// Returns sorted points with ~15 minute intervals.
    static func generate(
        bedtime: Date,
        wakeTime: Date,
        coolingIntensity: CoolingIntensity = .balanced,
        minTempF: Int = 68,
        maxTempF: Int = 86
    ) -> [Point] {
        let calendar = Calendar.current
        var wake = wakeTime
        if wake <= bedtime {
            wake = calendar.date(byAdding: .day, value: 1, to: wake) ?? wake
        }

        let sleepDuration = wake.timeIntervalSince(bedtime)

        // Map intensity ratios to the user's actual temp range
        // Deep sleep hits min, pre-wake hits max
        let baseTempF = 80
        let coolRange = baseTempF - minTempF  // e.g. 80-70 = 10
        let warmRange = maxTempF - baseTempF  // e.g. 83-80 = 3

        // Intensity ratios: how much of the available range each phase uses
        // deepSleep = 100% of cool range, fallAsleep = 60%, maintain = 50%
        // preWake = 100% of warm range, warmUp = 30%
        let ratios = coolingIntensity.ratios

        let offsets = (
            warmUp: Int(Double(warmRange) * ratios.warmUp),
            fallAsleep: -Int(Double(coolRange) * ratios.fallAsleep),
            deepSleep: -coolRange,  // always hits min
            maintain: -Int(Double(coolRange) * ratios.maintain),
            preWake: warmRange  // always hits max
        )

        var points: [Point] = []

        // Water takes ~15-20 min to change 1°F in the tubing.
        // All transitions are gradual — no sharp steps.

        // Wind down: bedtime -45min → bedtime (gentle warm)
        let windDownStart = bedtime.addingTimeInterval(-45 * 60)
        points.append(Point(time: windDownStart, tempOffset: 0, phase: .warmUp))
        points.append(Point(time: bedtime.addingTimeInterval(-30 * 60), tempOffset: offsets.warmUp / 3, phase: .warmUp))
        points.append(Point(time: bedtime.addingTimeInterval(-15 * 60), tempOffset: offsets.warmUp * 2 / 3, phase: .warmUp))
        points.append(Point(time: bedtime, tempOffset: offsets.warmUp, phase: .warmUp))

        // Fall asleep: bedtime → +90min (slow cool ramp — water needs time)
        let coolRamp = min(90 * 60, sleepDuration * 0.15)
        points.append(Point(time: bedtime.addingTimeInterval(coolRamp * 0.25), tempOffset: offsets.warmUp / 2, phase: .coolDown))
        points.append(Point(time: bedtime.addingTimeInterval(coolRamp * 0.5), tempOffset: offsets.fallAsleep / 2, phase: .coolDown))
        points.append(Point(time: bedtime.addingTimeInterval(coolRamp * 0.75), tempOffset: offsets.fallAsleep * 3 / 4, phase: .coolDown))
        points.append(Point(time: bedtime.addingTimeInterval(coolRamp), tempOffset: offsets.fallAsleep, phase: .coolDown))

        // Transition to deep: another 30-60min to reach coldest
        let deepTransition = min(60 * 60, sleepDuration * 0.1)
        let deepStart = bedtime.addingTimeInterval(coolRamp + deepTransition)
        points.append(Point(time: bedtime.addingTimeInterval(coolRamp + deepTransition * 0.5), tempOffset: (offsets.fallAsleep + offsets.deepSleep) / 2, phase: .deepSleep))
        points.append(Point(time: deepStart, tempOffset: offsets.deepSleep, phase: .deepSleep))

        // Deep sleep: hold coldest for ~2-3h
        let deepSleepEnd = bedtime.addingTimeInterval(min(3.5 * 3600, sleepDuration * 0.45))
        let deepMid = Date(timeIntervalSince1970: (deepStart.timeIntervalSince1970 + deepSleepEnd.timeIntervalSince1970) / 2)
        points.append(Point(time: deepMid, tempOffset: offsets.deepSleep, phase: .deepSleep))
        points.append(Point(time: deepSleepEnd, tempOffset: offsets.deepSleep, phase: .deepSleep))

        // Gradual rise to maintain: ~45min transition
        let maintainStart = deepSleepEnd.addingTimeInterval(45 * 60)
        points.append(Point(time: deepSleepEnd.addingTimeInterval(15 * 60), tempOffset: offsets.deepSleep + (offsets.maintain - offsets.deepSleep) / 3, phase: .maintain))
        points.append(Point(time: deepSleepEnd.addingTimeInterval(30 * 60), tempOffset: offsets.deepSleep + (offsets.maintain - offsets.deepSleep) * 2 / 3, phase: .maintain))
        points.append(Point(time: maintainStart, tempOffset: offsets.maintain, phase: .maintain))

        // Maintain: flat hold
        let preWakeStart = wake.addingTimeInterval(-45 * 60)
        if preWakeStart > maintainStart.addingTimeInterval(30 * 60) {
            let mid = Date(timeIntervalSince1970: (maintainStart.timeIntervalSince1970 + preWakeStart.timeIntervalSince1970) / 2)
            points.append(Point(time: mid, tempOffset: offsets.maintain, phase: .maintain))
        }
        points.append(Point(time: preWakeStart, tempOffset: offsets.maintain, phase: .maintain))

        // Pre-wake: gradual warm over 45min
        points.append(Point(time: preWakeStart.addingTimeInterval(15 * 60), tempOffset: offsets.maintain + (offsets.preWake - offsets.maintain) / 3, phase: .preWake))
        points.append(Point(time: preWakeStart.addingTimeInterval(30 * 60), tempOffset: offsets.maintain + (offsets.preWake - offsets.maintain) * 2 / 3, phase: .preWake))
        points.append(Point(time: wake, tempOffset: offsets.preWake, phase: .preWake))

        // Wake: slow return to neutral over 30min
        points.append(Point(time: wake.addingTimeInterval(10 * 60), tempOffset: offsets.preWake * 2 / 3, phase: .wake))
        points.append(Point(time: wake.addingTimeInterval(20 * 60), tempOffset: offsets.preWake / 3, phase: .wake))
        points.append(Point(time: wake.addingTimeInterval(30 * 60), tempOffset: 0, phase: .wake))

        return points.sorted { $0.time < $1.time }
    }

    /// Convert curve points to schedule set points (HH:mm → tempF pairs).
    /// If multiple points share the same HH:mm timestamp, the last one wins.
    static func toScheduleTemperatures(_ points: [Point], baseTempF: Int = 80) -> [String: Int] {
        var result: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        // Sample at key transitions only
        for point in points {
            let key = formatter.string(from: point.time)
            result[key] = baseTempF + point.tempOffset
        }
        return result
    }
}

// MARK: - Cooling Intensity

enum CoolingIntensity: String, CaseIterable, Identifiable, Sendable {
    case cool = "Cool"
    case balanced = "Balanced"
    case warm = "Warm"

    var id: String { rawValue }

    var offsets: (warmUp: Int, fallAsleep: Int, deepSleep: Int, maintain: Int, preWake: Int) {
        switch self {
        case .cool:     (+1, -6, -8, -6, +2)
        case .balanced: (+2, -4, -6, -4, +4)
        case .warm:     (+3, -2, -4, -2, +6)
        }
    }

    /// Ratios of the available temp range each phase uses (0.0 to 1.0)
    /// deepSleep and preWake always use 100% — they define the min/max
    var ratios: (warmUp: Double, fallAsleep: Double, maintain: Double) {
        switch self {
        case .cool:     (0.2, 0.7, 0.6)    // aggressive cooling
        case .balanced: (0.3, 0.6, 0.5)    // moderate
        case .warm:     (0.5, 0.4, 0.3)    // gentle cooling
        }
    }

    var description: String {
        switch self {
        case .cool: "Extra cooling for hot sleepers"
        case .balanced: "Science-backed defaults for most people"
        case .warm: "Gentler cooling, warmer wake-up"
        }
    }
}
