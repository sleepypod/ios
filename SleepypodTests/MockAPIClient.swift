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

    var stageModelResponse: Result<PodStageModelResponse, Error> = .success(PodStageModelResponse(model: nil, uploadedAt: nil))
    var getStageModelCalls = 0
    func getStageModel(side: Side) async throws -> PodStageModelResponse {
        getStageModelCalls += 1
        return try stageModelResponse.get()
    }

    var importStages: (Side, [PodWatchUpload.Segment]) throws -> Int = { _, segments in segments.count }
    var importVitals: (Side, [PodWatchUpload.Sample]) throws -> Int = { _, samples in samples.count }
    var importSamples: (Side, PodWatchUpload.Metric, [PodWatchUpload.Sample]) throws -> Int = { _, _, samples in samples.count }
    var importCalls = 0
    func importReferenceStages(side: Side, segments: [PodWatchUpload.Segment]) async throws -> Int {
        importCalls += 1
        return try importStages(side, segments)
    }
    func importReferenceVitals(side: Side, heartRate: [PodWatchUpload.Sample]) async throws -> Int {
        importCalls += 1
        return try importVitals(side, heartRate)
    }
    func importReferenceSamples(side: Side, metric: PodWatchUpload.Metric, samples: [PodWatchUpload.Sample]) async throws -> Int {
        importCalls += 1
        return try importSamples(side, metric, samples)
    }

    var uploadMotion: (Side, Data) throws -> WatchMotionUploadResult = { side, _ in
        WatchMotionUploadResult(id: 1, side: side, version: "watch-motion-v2", recordedFromMs: 0, recordedToMs: 0,
                                bins: 0, trimmedBins: 0, status: .created)
    }
    var uploadMotionCalls: [(Side, Data)] = []
    func uploadWatchMotion(side: Side, file: Data) async throws -> WatchMotionUploadResult {
        uploadMotionCalls.append((side, file))
        return try uploadMotion(side, file)
    }

    func getDeviceStatus() async throws -> DeviceStatus { throw APIError.noBaseURL }
    func updateDeviceStatus(_ update: DeviceStatusUpdate) async throws {}
    func getSettings() async throws -> PodSettings { throw APIError.noBaseURL }
    func updateSettings(_ settings: PodSettings) async throws -> PodSettings { throw APIError.noBaseURL }
    func getSchedules() async throws -> Schedules { throw APIError.noBaseURL }
    func updateSchedules(_ schedules: Schedules, days: Set<DayOfWeek>? = nil) async throws -> Schedules { throw APIError.noBaseURL }
    func getLogSources() async throws -> [LogSource] { [] }
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
    func getBedTempHistory(start: Date, end: Date, limit: Int, unit: String) async throws -> [BedTempReading] { [] }
    func updateSleepRecord(id: Int, enteredBedAt: Date?, leftBedAt: Date?) async throws {}
    func deleteSleepRecord(id: Int) async throws {}
    func dismissPrimeNotification() async throws {}
    func startRunOnce(side: Side, setPoints: [RunOnceSetPoint], wakeTime: String) async throws -> RunOnceStartResponse { RunOnceStartResponse(sessionId: 0, expiresAt: 0) }
    func getActiveRunOnce(side: Side) async throws -> RunOnceSession? { nil }
    func cancelRunOnce(side: Side) async throws {}

    func getInternetStatus() async throws -> Bool { internetBlocked }

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
