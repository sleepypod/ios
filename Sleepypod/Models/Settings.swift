import Foundation

enum TemperatureFormat: String, Codable, Sendable {
    case celsius
    case fahrenheit
    case relative  // Eight Sleep style: +3, -2, 0
}

enum TapConfigType: String, Codable, Sendable {
    case temperature
    case alarm
}

enum TempChangeDirection: String, Codable, Sendable {
    case increment
    case decrement
}

enum AlarmBehavior: String, Codable, Sendable {
    case snooze
    case dismiss
}

enum InactiveAlarmBehavior: String, Codable, Sendable {
    case power
    case none
}

enum TapConfig: Codable, Sendable {
    case temperature(change: TempChangeDirection, amount: Int)
    case alarm(behavior: AlarmBehavior, snoozeDuration: Int, inactiveAlarmBehavior: InactiveAlarmBehavior)

    enum CodingKeys: String, CodingKey {
        case type, change, amount, behavior, snoozeDuration, inactiveAlarmBehavior
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TapConfigType.self, forKey: .type)
        switch type {
        case .temperature:
            let change = try container.decode(TempChangeDirection.self, forKey: .change)
            let amount = try container.decode(Int.self, forKey: .amount)
            self = .temperature(change: change, amount: amount)
        case .alarm:
            let behavior = try container.decode(AlarmBehavior.self, forKey: .behavior)
            let snoozeDuration = try container.decode(Int.self, forKey: .snoozeDuration)
            let inactiveBehavior = try container.decode(InactiveAlarmBehavior.self, forKey: .inactiveAlarmBehavior)
            self = .alarm(behavior: behavior, snoozeDuration: snoozeDuration, inactiveAlarmBehavior: inactiveBehavior)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .temperature(let change, let amount):
            try container.encode(TapConfigType.temperature, forKey: .type)
            try container.encode(change, forKey: .change)
            try container.encode(amount, forKey: .amount)
        case .alarm(let behavior, let snoozeDuration, let inactiveBehavior):
            try container.encode(TapConfigType.alarm, forKey: .type)
            try container.encode(behavior, forKey: .behavior)
            try container.encode(snoozeDuration, forKey: .snoozeDuration)
            try container.encode(inactiveBehavior, forKey: .inactiveAlarmBehavior)
        }
    }
}

struct TapSettings: Codable, Sendable {
    var doubleTap: TapConfig
    var tripleTap: TapConfig
    var quadTap: TapConfig
}

struct ScheduleOverrides: Codable, Sendable {
    var temperatureSchedules: TemperatureScheduleOverride
    var alarm: AlarmOverride
}

struct TemperatureScheduleOverride: Codable, Sendable {
    var disabled: Bool
    var expiresAt: String
}

struct AlarmOverride: Codable, Sendable {
    var disabled: Bool
    var timeOverride: String
    var expiresAt: String
}

struct SideSettings: Codable, Sendable {
    var name: String
    var awayMode: Bool
    var scheduleOverrides: ScheduleOverrides
    var taps: TapSettings
}

struct PrimePodDaily: Codable, Sendable {
    var enabled: Bool
    var time: String  // "HH:mm"
}

struct PodSettings: Codable, Sendable {
    var id: String
    var timeZone: String
    var left: SideSettings
    var right: SideSettings
    var primePodDaily: PrimePodDaily
    var temperatureFormat: TemperatureFormat
    var rebootDaily: Bool
    var rebootTime: String  // "HH:mm"
}
