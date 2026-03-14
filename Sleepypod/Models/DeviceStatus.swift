import Foundation

struct SideStatus: Codable, Sendable {
    var currentTemperatureLevel: Int
    var currentTemperatureF: Int
    var targetTemperatureF: Int
    var secondsRemaining: Int
    var isOn: Bool
    var isAlarmVibrating: Bool
    var taps: TapCounts?
}

struct TapCounts: Codable, Sendable {
    var doubleTap: Int
    var tripleTap: Int
    var quadTap: Int
}

struct DeviceHardwareSettings: Codable, Sendable {
    var v: Int
    var gainLeft: Double
    var gainRight: Double
    var ledBrightness: Int
}

struct FreeSleepInfo: Codable, Sendable {
    var version: String
    var branch: String
}

struct DeviceStatus: Codable, Sendable {
    var left: SideStatus
    var right: SideStatus
    var waterLevel: String
    var isPriming: Bool
    var settings: DeviceHardwareSettings
    var coverVersion: String
    var hubVersion: String
    var freeSleep: FreeSleepInfo
    var wifiStrength: Int

    func status(for side: Side) -> SideStatus {
        switch side {
        case .left: left
        case .right: right
        }
    }
}

// For partial updates via POST /api/deviceStatus
struct DeviceStatusUpdate: Encodable, Sendable {
    var left: SideStatusUpdate?
    var right: SideStatusUpdate?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(left, forKey: .left)
        try container.encodeIfPresent(right, forKey: .right)
    }

    enum CodingKeys: String, CodingKey {
        case left, right
    }
}

struct SideStatusUpdate: Encodable, Sendable {
    var targetTemperatureF: Int?
    var isOn: Bool?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(targetTemperatureF, forKey: .targetTemperatureF)
        try container.encodeIfPresent(isOn, forKey: .isOn)
    }

    enum CodingKeys: String, CodingKey {
        case targetTemperatureF, isOn
    }
}
