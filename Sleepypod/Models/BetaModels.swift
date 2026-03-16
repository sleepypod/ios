import Foundation

// MARK: - System Version (#184)

struct SystemVersion: Decodable, Sendable {
    let branch: String
    let commitHash: String
    let commitTitle: String
    let buildDate: String

    var shortHash: String { String(commitHash.prefix(7)) }
}

// MARK: - Alarm Snooze (#183)

struct SnoozeResponse: Decodable, Sendable {
    let success: Bool
    let snoozeUntil: Int  // unix timestamp

    var snoozeUntilDate: Date { Date(timeIntervalSince1970: TimeInterval(snoozeUntil)) }

    var remainingFormatted: String {
        let remaining = Int(snoozeUntilDate.timeIntervalSinceNow)
        guard remaining > 0 else { return "Expired" }
        let minutes = remaining / 60
        let seconds = remaining % 60
        return "\(minutes)m \(seconds)s"
    }
}

struct SnoozeStatus: Decodable, Sendable {
    let active: Bool
    let snoozeUntil: Int?
    let remainingSeconds: Int?
}

// MARK: - Water Level Monitoring (#181)

struct WaterLevelReading: Decodable, Sendable {
    let id: Int?
    let level: String       // "ok" or "low"
    let rawValue: String?
    let timestamp: String?  // ISO8601
}

struct WaterLevelTrend: Decodable, Sendable {
    let totalReadings: Int
    let okPercent: Int
    let lowPercent: Int
    let trend: String       // "stable", "declining", "rising", "insufficient_data"
    let latestLevel: String?
}

struct WaterLevelAlert: Decodable, Sendable, Identifiable {
    let id: Int
    let level: String
    let dismissed: Bool
    let timestamp: String?
}

// MARK: - Ambient Light (#185)

struct AmbientLightReading: Decodable, Sendable {
    let id: Int?
    let lux: Double
    let timestamp: String?  // ISO8601
}

// MARK: - Prime Notification (#188)

struct PrimeCompletedNotification: Decodable, Sendable {
    let timestamp: Int  // unix
}
