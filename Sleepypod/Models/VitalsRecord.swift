import Foundation

struct VitalsRecord: Codable, Sendable, Identifiable {
    var id: Int
    var side: String
    var heartRate: Double?
    var hrv: Double?
    var breathingRate: Double?

    // Handles both unix timestamp (free-sleep) and ISO8601 string (sleepypod-core)
    private var _timestamp: TimeInterval

    var date: Date {
        Date(timeIntervalSince1970: _timestamp)
    }

    /// Memberwise init for tests and internal use
    init(id: Int, side: String = "left", heartRate: Double? = nil, hrv: Double? = nil, breathingRate: Double? = nil, date: Date = Date()) {
        self.id = id
        self.side = side
        self.heartRate = heartRate
        self.hrv = hrv
        self.breathingRate = breathingRate
        self._timestamp = date.timeIntervalSince1970
    }

    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    enum CodingKeys: String, CodingKey {
        case id, side, timestamp, heartRate, hrv, breathingRate
        // free-sleep snake_case aliases
        case heart_rate, breathing_rate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        side = try c.decode(String.self, forKey: .side)
        heartRate = try c.decodeIfPresent(Double.self, forKey: .heartRate)
            ?? c.decodeIfPresent(Double.self, forKey: .heart_rate)
        hrv = try c.decodeIfPresent(Double.self, forKey: .hrv)
        breathingRate = try c.decodeIfPresent(Double.self, forKey: .breathingRate)
            ?? c.decodeIfPresent(Double.self, forKey: .breathing_rate)

        // Parse timestamp — try Int first (unix), then String (ISO8601)
        if let unix = try? c.decode(Int.self, forKey: .timestamp) {
            _timestamp = TimeInterval(unix)
        } else if let iso = try? c.decode(String.self, forKey: .timestamp) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            _timestamp = fmt.date(from: iso)?.timeIntervalSince1970
                ?? ISO8601DateFormatter().date(from: iso)?.timeIntervalSince1970
                ?? 0
        } else {
            _timestamp = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(side, forKey: .side)
        try c.encode(Int(_timestamp), forKey: .timestamp)
        try c.encodeIfPresent(heartRate, forKey: .heartRate)
        try c.encodeIfPresent(hrv, forKey: .hrv)
        try c.encodeIfPresent(breathingRate, forKey: .breathingRate)
    }
}

struct VitalsSummary: Codable, Sendable {
    var avgHeartRate: Double?
    var minHeartRate: Double?
    var maxHeartRate: Double?
    var avgHRV: Double?
    var avgBreathingRate: Double?
}
