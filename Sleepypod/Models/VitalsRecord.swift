import Foundation

struct VitalsRecord: Codable, Sendable, Identifiable {
    var id: Int
    var side: String
    var timestamp: Int       // Unix timestamp (5-minute interval)
    var heartRate: Double?
    var hrv: Double?
    var breathingRate: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case side
        case timestamp
        case heartRate = "heart_rate"
        case hrv
        case breathingRate = "breathing_rate"
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

struct VitalsSummary: Codable, Sendable {
    var avgHeartRate: Double?
    var minHeartRate: Double?
    var maxHeartRate: Double?
    var avgHRV: Double?
    var avgBreathingRate: Double?
}
