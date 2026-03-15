import Foundation

struct SleepRecord: Codable, Sendable, Identifiable {
    var id: Int
    var side: String
    var timesExitedBed: Int
    var presentIntervals: String?
    var notPresentIntervals: String?

    // Handles both unix timestamp (free-sleep) and ISO8601 string (sleepypod-core)
    private var _enteredBedAt: TimeInterval
    private var _leftBedAt: TimeInterval
    private var _sleepSeconds: Int

    enum CodingKeys: String, CodingKey {
        // sleepypod-core (camelCase)
        case id, side, enteredBedAt, leftBedAt, sleepDurationSeconds
        case timesExitedBed, presentIntervals, notPresentIntervals, createdAt
        // free-sleep (snake_case)
        case entered_bed_at, left_bed_at, sleep_period_seconds
        case times_exited_bed, present_intervals, not_present_intervals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        side = try c.decode(String.self, forKey: .side)

        timesExitedBed = (try? c.decode(Int.self, forKey: .timesExitedBed))
            ?? (try? c.decode(Int.self, forKey: .times_exited_bed)) ?? 0

        presentIntervals = (try? c.decodeIfPresent(String.self, forKey: .presentIntervals))
            ?? (try? c.decodeIfPresent(String.self, forKey: .present_intervals))
        notPresentIntervals = (try? c.decodeIfPresent(String.self, forKey: .notPresentIntervals))
            ?? (try? c.decodeIfPresent(String.self, forKey: .not_present_intervals))

        _sleepSeconds = (try? c.decode(Int.self, forKey: .sleepDurationSeconds))
            ?? (try? c.decode(Int.self, forKey: .sleep_period_seconds)) ?? 0

        _enteredBedAt = Self.parseTimestamp(c, keys: [.enteredBedAt, .entered_bed_at])
        _leftBedAt = Self.parseTimestamp(c, keys: [.leftBedAt, .left_bed_at])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(side, forKey: .side)
        try c.encode(_sleepSeconds, forKey: .sleepDurationSeconds)
        try c.encode(timesExitedBed, forKey: .timesExitedBed)
    }

    private static func parseTimestamp(_ c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> TimeInterval {
        for key in keys {
            if let unix = try? c.decode(Int.self, forKey: key) {
                return TimeInterval(unix)
            }
            if let iso = try? c.decode(String.self, forKey: key) {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
                    return date.timeIntervalSince1970
                }
            }
        }
        return 0
    }

    // MARK: - Computed

    var enteredBedDate: Date { Date(timeIntervalSince1970: _enteredBedAt) }
    var leftBedDate: Date { Date(timeIntervalSince1970: _leftBedAt) }
    var sleepPeriodSeconds: Int { _sleepSeconds }

    var durationHours: Double { Double(_sleepSeconds) / 3600.0 }

    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: enteredBedDate)
    }

    var bedtimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: enteredBedDate)
    }

    var wakeTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: leftBedDate)
    }

    var durationFormatted: String {
        let hours = _sleepSeconds / 3600
        let minutes = (_sleepSeconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
