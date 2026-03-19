import Foundation

struct MovementRecord: Codable, Sendable, Identifiable {
    var id: Int
    var side: String
    var totalMovement: Int

    private var _timestamp: TimeInterval

    enum CodingKeys: String, CodingKey {
        case id, side, timestamp, totalMovement, total_movement
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        side = try c.decode(String.self, forKey: .side)
        totalMovement = (try? c.decode(Int.self, forKey: .totalMovement))
            ?? (try? c.decode(Int.self, forKey: .total_movement)) ?? 0

        if let unix = try? c.decode(Int.self, forKey: .timestamp) {
            _timestamp = TimeInterval(unix)
        } else if let iso = try? c.decode(String.self, forKey: .timestamp) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            _timestamp = fmt.date(from: iso)?.timeIntervalSince1970
                ?? ISO8601DateFormatter().date(from: iso)?.timeIntervalSince1970 ?? 0
        } else {
            _timestamp = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(side, forKey: .side)
        try c.encode(Int(_timestamp), forKey: .timestamp)
        try c.encode(totalMovement, forKey: .totalMovement)
    }

    /// Memberwise init for tests and internal use
    init(id: Int, side: String = "left", totalMovement: Int = 0, date: Date = Date()) {
        self.id = id
        self.side = side
        self.totalMovement = totalMovement
        self._timestamp = date.timeIntervalSince1970
    }

    var timestamp: Int { Int(_timestamp) }
    var date: Date { Date(timeIntervalSince1970: _timestamp) }

    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
