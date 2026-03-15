import Foundation

protocol SleepypodProtocol: Sendable {
    func getDeviceStatus() async throws -> DeviceStatus
    func updateDeviceStatus(_ update: DeviceStatusUpdate) async throws
    func getSettings() async throws -> PodSettings
    func updateSettings(_ settings: PodSettings) async throws -> PodSettings
    func getSchedules() async throws -> Schedules
    func updateSchedules(_ schedules: Schedules) async throws -> Schedules
    func getServerStatus() async throws -> ServerStatus
    func getServices() async throws -> Services
    func updateServices(_ services: Services) async throws -> Services
    func getSleepRecords(side: Side?, start: Date?, end: Date?) async throws -> [SleepRecord]
    func getVitals(side: Side?, start: Date?, end: Date?) async throws -> [VitalsRecord]
    func getVitalsSummary(side: Side?, start: Date?, end: Date?) async throws -> VitalsSummary
    func getMovement(side: Side?, start: Date?, end: Date?) async throws -> [MovementRecord]
    func triggerAlarm(_ alarm: AlarmJob) async throws
    func reboot() async throws
    func setInternetAccess(blocked: Bool) async throws
    func getCalibrationStatus(side: Side) async throws -> CalibrationStatus
}
