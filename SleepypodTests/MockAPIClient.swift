import Foundation
@testable import Sleepypod

/// Mock API client for unit testing. Records calls and returns configurable responses.
class MockAPIClient: SleepypodProtocol, @unchecked Sendable {
    var internetBlocked = false
    var setInternetCalls: [(Bool)] = []
    var calibrationStatuses: [String: CalibrationStatus] = [:]
    var triggerCalibrationCalls: [(Side, String)] = []
    var triggerFullCalibrationCalls = 0

    // Track delays to simulate slow responses
    var responseDelay: TimeInterval = 0

    func getDeviceStatus() async throws -> DeviceStatus { throw APIError.noBaseURL }
    func updateDeviceStatus(_ update: DeviceStatusUpdate) async throws {}
    func getSettings() async throws -> PodSettings { throw APIError.noBaseURL }
    func updateSettings(_ settings: PodSettings) async throws -> PodSettings { throw APIError.noBaseURL }
    func getSchedules() async throws -> Schedules { throw APIError.noBaseURL }
    func updateSchedules(_ schedules: Schedules, days: Set<DayOfWeek>? = nil) async throws -> Schedules { throw APIError.noBaseURL }
    func getServerStatus() async throws -> ServerStatus { throw APIError.noBaseURL }
    func getServices() async throws -> Services { throw APIError.noBaseURL }
    func updateServices(_ services: Services) async throws -> Services { throw APIError.noBaseURL }
    func getSleepRecords(side: Side?, start: Date?, end: Date?) async throws -> [SleepRecord] { [] }
    func getVitals(side: Side?, start: Date?, end: Date?) async throws -> [VitalsRecord] { [] }
    func getVitalsSummary(side: Side?, start: Date?, end: Date?) async throws -> VitalsSummary { VitalsSummary(avgHeartRate: nil, minHeartRate: nil, maxHeartRate: nil, avgHRV: nil, avgBreathingRate: nil) }
    func getMovement(side: Side?, start: Date?, end: Date?) async throws -> [MovementRecord] { [] }
    func triggerAlarm(_ alarm: AlarmJob) async throws {}
    func clearAlarm(side: Side) async throws {}
    func reboot() async throws {}
    func getDiskUsage() async throws -> DiskUsage { throw APIError.noBaseURL }
    func getFileCount() async throws -> FileCount { throw APIError.noBaseURL }
    func getVersion() async throws -> SystemVersion { SystemVersion(branch: "main", commitHash: "abc1234", commitTitle: "test", buildDate: "2026-03-16") }
    func snoozeAlarm(side: Side, duration: Int) async throws -> SnoozeResponse { SnoozeResponse(success: true, snoozeUntil: Int(Date().timeIntervalSince1970) + duration) }
    func getWaterLevelLatest() async throws -> WaterLevelReading? { nil }
    func getWaterLevelTrend(hours: Int) async throws -> WaterLevelTrend { WaterLevelTrend(totalReadings: 0, okPercent: 100, lowPercent: 0, trend: "stable", latestLevel: "ok") }
    func getAmbientLightLatest() async throws -> AmbientLightReading? { nil }
    func updateSleepRecord(id: Int, enteredBedAt: Date?, leftBedAt: Date?) async throws {}
    func deleteSleepRecord(id: Int) async throws {}
    func dismissPrimeNotification() async throws {}

    func setInternetAccess(blocked: Bool) async throws {
        if responseDelay > 0 { try? await Task.sleep(for: .seconds(responseDelay)) }
        setInternetCalls.append(blocked)
        internetBlocked = blocked
    }

    func getCalibrationStatus(side: Side) async throws -> CalibrationStatus {
        if responseDelay > 0 { try? await Task.sleep(for: .seconds(responseDelay)) }
        guard let status = calibrationStatuses[side.rawValue] else {
            throw APIError.invalidResponse(statusCode: 404)
        }
        return status
    }

    func triggerCalibration(side: Side, sensorType: String) async throws -> CalibrationTriggerResponse {
        triggerCalibrationCalls.append((side, sensorType))
        return CalibrationTriggerResponse(triggered: true, message: "Queued")
    }

    func triggerFullCalibration() async throws -> CalibrationTriggerResponse {
        triggerFullCalibrationCalls += 1
        return CalibrationTriggerResponse(triggered: true, message: "Full calibration queued")
    }
}
