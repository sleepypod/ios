import Foundation

enum HTTPMethod: String, Sendable {
    case GET
    case POST
    case PUT
    case DELETE
}

enum APIEndpoint: Sendable {
    case deviceStatus
    case updateDeviceStatus
    case schedules
    case updateSchedules
    case settings
    case updateSettings
    case serverStatus
    case services
    case updateServices
    case alarm
    case sleepRecords(side: Side?, start: Date?, end: Date?)
    case vitals(side: Side?, start: Date?, end: Date?)
    case vitalsSummary(side: Side?, start: Date?, end: Date?)
    case movement(side: Side?, start: Date?, end: Date?)

    var path: String {
        switch self {
        case .deviceStatus, .updateDeviceStatus:
            "/api/deviceStatus"
        case .schedules, .updateSchedules:
            "/api/schedules"
        case .settings, .updateSettings:
            "/api/settings"
        case .serverStatus:
            "/api/serverStatus"
        case .services, .updateServices:
            "/api/services"
        case .alarm:
            "/api/alarm"
        case .sleepRecords:
            "/api/metrics/sleep"
        case .vitals:
            "/api/metrics/vitals"
        case .vitalsSummary:
            "/api/metrics/vitals/summary"
        case .movement:
            "/api/metrics/movement"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .deviceStatus, .schedules, .settings, .serverStatus, .services,
             .sleepRecords, .vitals, .vitalsSummary, .movement:
            .GET
        case .updateDeviceStatus, .updateSchedules, .updateSettings,
             .updateServices, .alarm:
            .POST
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .sleepRecords(let side, let start, let end):
            return buildMetricsQuery(side: side, start: start, end: end, useISO: true)
        case .vitals(let side, let start, let end),
             .vitalsSummary(let side, let start, let end),
             .movement(let side, let start, let end):
            return buildMetricsQuery(side: side, start: start, end: end, useISO: false)
        default:
            return nil
        }
    }

    private func buildMetricsQuery(side: Side?, start: Date?, end: Date?, useISO: Bool) -> [URLQueryItem]? {
        var items: [URLQueryItem] = []
        if let side {
            items.append(URLQueryItem(name: "side", value: side.rawValue))
        }
        if let start {
            let value = useISO ? ISO8601DateFormatter().string(from: start) : "\(Int(start.timeIntervalSince1970))"
            items.append(URLQueryItem(name: "startTime", value: value))
        }
        if let end {
            let value = useISO ? ISO8601DateFormatter().string(from: end) : "\(Int(end.timeIntervalSince1970))"
            items.append(URLQueryItem(name: "endTime", value: value))
        }
        return items.isEmpty ? nil : items
    }
}
