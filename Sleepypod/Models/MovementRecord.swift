import Foundation

struct MovementRecord: Codable, Sendable, Identifiable {
    var id: Int
    var timestamp: Int   // Unix timestamp
    var side: String
    var totalMovement: Int

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case side
        case totalMovement = "total_movement"
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
