import Foundation

// Stub type for hook-generated reportVitalsBatch protocol requirement
struct VitalsReport: Codable, Sendable {
    var side: String
    var timestamp: Int
    var heartRate: Double?
    var hrv: Double?
    var breathingRate: Double?
}
