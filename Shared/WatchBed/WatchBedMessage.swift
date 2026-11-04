import Foundation

/// What the Watch asks the iPhone to do with the pod, and what the iPhone answers. The Watch never talks to the
/// pod itself: the iPhone already knows where the pod is and how to reach it. Each message is JSON under one key.
enum WatchBed {
    static let messageKey = "watchBed"

    enum Side: String, Codable, Sendable, CaseIterable {
        case left, right
    }

    enum Request: Codable, Sendable, Equatable {
        case status
        case setPower(sides: [Side], on: Bool)
        case setTemperature(sides: [Side], fahrenheit: Int)
        case stopAlarm(side: Side)
        case snoozeAlarm(side: Side, minutes: Int)
        /// Sends the Watch's movement recordings and last nights' Health readings to the pod.
        case sendNightToPod
    }

    enum Unit: String, Codable, Sendable {
        case fahrenheit, celsius, relative
    }

    struct SideState: Codable, Sendable, Equatable {
        var side: Side
        var name: String
        var isOn: Bool
        var currentF: Int?
        var targetF: Int?
        var isAlarmVibrating: Bool
    }

    struct Snapshot: Codable, Sendable, Equatable {
        var sides: [SideState]
        var defaultSide: Side
        var unit: Unit
        var waterLow: Bool
        var isPriming: Bool
        var takenAt: Date

        func state(_ side: Side) -> SideState? { sides.first { $0.side == side } }

        var alarmSide: Side? { sides.first { $0.isAlarmVibrating }?.side }
    }

    struct Reply: Codable, Sendable, Equatable {
        var snapshot: Snapshot?
        /// A short line to show under the controls, such as what was sent or why a command failed.
        var message: String?
        var failed = false
    }

    static let minF = 55
    static let maxF = 110
    static let baseF = 80

    static func clamp(_ fahrenheit: Int) -> Int { min(maxF, max(minF, fahrenheit)) }

    /// Big-number text in the unit the iPhone shows: "76°", "24°" or the signed offset from 80°F.
    static func valueText(_ fahrenheit: Int, unit: Unit) -> String {
        switch unit {
        case .fahrenheit: return "\(fahrenheit)°"
        case .celsius: return "\(Int((Double(fahrenheit - 32) * 5 / 9).rounded()))°"
        case .relative:
            let offset = fahrenheit - baseF
            return offset > 0 ? "+\(offset)" : offset < 0 ? "−\(-offset)" : "0"
        }
    }

    static func message<T: Encodable>(_ value: T) throws -> [String: Any] {
        [messageKey: try JSONEncoder().encode(value)]
    }

    static func decode<T: Decodable>(_ type: T.Type, from message: [String: Any]) throws -> T {
        guard let data = message[messageKey] as? Data else { throw DecodingError.valueNotFound(Data.self, .init(codingPath: [], debugDescription: "No \(messageKey) payload")) }
        return try JSONDecoder().decode(type, from: data)
    }
}
