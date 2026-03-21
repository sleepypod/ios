import Foundation

/// A sleep profile encapsulates temperature preferences as a persona.
/// Each profile maps to SleepCurve generation parameters so the user
/// picks a personality instead of manipulating raw curves.
struct SmartProfile: Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let detail: String
    let intensity: CoolingIntensity
    let minTempF: Int
    let maxTempF: Int
    /// Phase duration adjustments (multipliers on default durations)
    let deepSleepDurationMultiplier: Double
    let warmUpDurationMultiplier: Double

    func generateCurve(bedtime: Date, wakeTime: Date) -> [SleepCurve.Point] {
        SleepCurve.generate(
            bedtime: bedtime,
            wakeTime: wakeTime,
            coolingIntensity: intensity,
            minTempF: minTempF,
            maxTempF: maxTempF
        )
    }
}

// MARK: - Built-in Profiles

extension SmartProfile {
    static let hotSleeper = SmartProfile(
        id: "hot",
        name: "Hot Sleeper",
        icon: "flame.fill",
        description: "Aggressive cooling for people who run warm",
        detail: "Drops temperature quickly after bedtime and holds a deep cold valley for longer. Best for those who wake up sweating or kick covers off.",
        intensity: .cool,
        minTempF: 66,
        maxTempF: 82,
        deepSleepDurationMultiplier: 1.2,
        warmUpDurationMultiplier: 0.8
    )

    static let coldSleeper = SmartProfile(
        id: "cold",
        name: "Cold Sleeper",
        icon: "snowflake",
        description: "Gentle cooling with a warmer baseline",
        detail: "Minimal temperature drop with a warm pre-wake ramp. Best for those who always feel cold in bed or use heavy blankets.",
        intensity: .warm,
        minTempF: 74,
        maxTempF: 88,
        deepSleepDurationMultiplier: 0.8,
        warmUpDurationMultiplier: 1.3
    )

    static let balanced = SmartProfile(
        id: "balanced",
        name: "Balanced",
        icon: "circle.lefthalf.filled",
        description: "Science-backed defaults for most people",
        detail: "Follows research-based temperature curves from Heller 2012 and Kräuchi 2007. A good starting point before personalizing.",
        intensity: .balanced,
        minTempF: 70,
        maxTempF: 85,
        deepSleepDurationMultiplier: 1.0,
        warmUpDurationMultiplier: 1.0
    )

    static let recovery = SmartProfile(
        id: "recovery",
        name: "Recovery",
        icon: "figure.run",
        description: "Extra cooling for exercise recovery nights",
        detail: "Extended deep-cold phase in the first half of the night promotes growth hormone release and muscle recovery. Warmer second half for comfort.",
        intensity: .cool,
        minTempF: 65,
        maxTempF: 84,
        deepSleepDurationMultiplier: 1.4,
        warmUpDurationMultiplier: 0.7
    )

    static let allProfiles: [SmartProfile] = [.hotSleeper, .coldSleeper, .balanced]
}
