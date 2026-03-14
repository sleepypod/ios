import Foundation

enum ServiceStatus: String, Codable, Sendable {
    case failed
    case healthy
    case notStarted = "not_started"
    case restarting
    case retrying
    case started

    var isHealthy: Bool {
        self == .healthy || self == .started
    }

    var displayName: String {
        switch self {
        case .failed: "Failed"
        case .healthy: "Healthy"
        case .notStarted: "Not Started"
        case .restarting: "Restarting"
        case .retrying: "Retrying"
        case .started: "Started"
        }
    }
}

struct StatusInfo: Codable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var status: ServiceStatus
    var description: String
    var message: String
    var timestamp: String?
}

struct ServerStatus: Codable, Sendable {
    var alarmSchedule: StatusInfo
    var database: StatusInfo
    var express: StatusInfo
    var franken: StatusInfo
    var frankenMonitor: StatusInfo
    var jobs: StatusInfo
    var logger: StatusInfo
    var powerSchedule: StatusInfo
    var primeSchedule: StatusInfo
    var rebootSchedule: StatusInfo
    var systemDate: StatusInfo
    var temperatureSchedule: StatusInfo
    var analyzeSleepLeft: StatusInfo?
    var analyzeSleepRight: StatusInfo?
    var biometricsInstallation: StatusInfo?
    var biometricsStream: StatusInfo?
    var biometricsCalibrationLeft: StatusInfo?
    var biometricsCalibrationRight: StatusInfo?

    var allStatuses: [StatusInfo] {
        var statuses = [
            alarmSchedule, database, express, franken, frankenMonitor,
            jobs, logger, powerSchedule, primeSchedule, rebootSchedule,
            systemDate, temperatureSchedule
        ]
        if let s = analyzeSleepLeft { statuses.append(s) }
        if let s = analyzeSleepRight { statuses.append(s) }
        if let s = biometricsInstallation { statuses.append(s) }
        if let s = biometricsStream { statuses.append(s) }
        if let s = biometricsCalibrationLeft { statuses.append(s) }
        if let s = biometricsCalibrationRight { statuses.append(s) }
        return statuses
    }

    var healthyCount: Int {
        allStatuses.filter(\.status.isHealthy).count
    }

    var totalCount: Int {
        allStatuses.count
    }
}

// Categories for the status screen
struct ServiceCategory: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let description: String
    let iconName: String
    let iconColorHex: String
    let services: [StatusInfo]

    var healthyCount: Int {
        services.filter(\.status.isHealthy).count
    }
}
