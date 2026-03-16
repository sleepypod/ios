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
        coolingIntensity: CoolingIntensity = .balanced
    ) -> [Point] {
        let calendar = Calendar.current
        var wake = wakeTime
        // Handle wake time being next day
        if wake <= bedtime {
            wake = calendar.date(byAdding: .day, value: 1, to: wake) ?? wake
        }

        let sleepDuration = wake.timeIntervalSince(bedtime)
        let offsets = coolingIntensity.offsets

        var points: [Point] = []

        // Wind down: bedtime -30min → bedtime (warm slightly)
        let windDownStart = bedtime.addingTimeInterval(-30 * 60)
        points.append(Point(time: windDownStart, tempOffset: 0, phase: .warmUp))
        points.append(Point(time: bedtime.addingTimeInterval(-15 * 60), tempOffset: offsets.warmUp / 2, phase: .warmUp))
        points.append(Point(time: bedtime, tempOffset: offsets.warmUp, phase: .warmUp))

        // Fall asleep: bedtime → +45min (cool down gradually)
        points.append(Point(time: bedtime.addingTimeInterval(15 * 60), tempOffset: offsets.fallAsleep / 2, phase: .coolDown))
        points.append(Point(time: bedtime.addingTimeInterval(30 * 60), tempOffset: offsets.fallAsleep, phase: .coolDown))
        points.append(Point(time: bedtime.addingTimeInterval(45 * 60), tempOffset: (offsets.fallAsleep + offsets.deepSleep) / 2, phase: .coolDown))

        // Deep sleep: +1h → +3h (coldest, with slight variation)
        let deepSleepEnd = bedtime.addingTimeInterval(min(3 * 3600, sleepDuration * 0.4))
        points.append(Point(time: bedtime.addingTimeInterval(60 * 60), tempOffset: offsets.deepSleep, phase: .deepSleep))
        let deepMid = bedtime.addingTimeInterval((60 * 60 + deepSleepEnd.timeIntervalSince(bedtime)) / 2)
        points.append(Point(time: deepMid, tempOffset: offsets.deepSleep, phase: .deepSleep))
        points.append(Point(time: deepSleepEnd, tempOffset: offsets.deepSleep, phase: .deepSleep))

        // Transition to maintain
        let transitionEnd = deepSleepEnd.addingTimeInterval(30 * 60)
        points.append(Point(time: transitionEnd, tempOffset: offsets.maintain, phase: .maintain))

        // Maintain: flat until pre-wake
        let preWakeStart = wake.addingTimeInterval(-30 * 60)
        if preWakeStart > transitionEnd.addingTimeInterval(30 * 60) {
            let maintainMid = transitionEnd.addingTimeInterval(preWakeStart.timeIntervalSince(transitionEnd) / 2)
            points.append(Point(time: maintainMid, tempOffset: offsets.maintain, phase: .maintain))
        }
        points.append(Point(time: preWakeStart, tempOffset: offsets.maintain, phase: .maintain))

        // Pre-wake: gradual warm up
        points.append(Point(time: preWakeStart.addingTimeInterval(10 * 60), tempOffset: offsets.preWake / 2, phase: .preWake))
        points.append(Point(time: wake.addingTimeInterval(-5 * 60), tempOffset: offsets.preWake, phase: .preWake))
        points.append(Point(time: wake, tempOffset: offsets.preWake, phase: .preWake))

        // Wake: return to neutral
        points.append(Point(time: wake.addingTimeInterval(10 * 60), tempOffset: offsets.preWake / 2, phase: .wake))
        points.append(Point(time: wake.addingTimeInterval(20 * 60), tempOffset: 0, phase: .wake))

        return points.sorted { $0.time < $1.time }
    }

    /// Convert curve points to schedule set points (HH:mm → tempF pairs)
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

    var description: String {
        switch self {
        case .cool: "Extra cooling for hot sleepers"
        case .balanced: "Science-backed defaults for most people"
        case .warm: "Gentler cooling, warmer wake-up"
        }
    }
}
