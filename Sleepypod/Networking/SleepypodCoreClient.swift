import Foundation

/// tRPC client for sleepypod-core (Next.js backend).
///
/// Translates `SleepypodProtocol` calls into tRPC HTTP requests.
/// tRPC queries use GET with input as a URL-encoded JSON param.
/// tRPC mutations use POST with JSON body `{"json": input}`.
///
/// Data shape differences between free-sleep and sleepypod-core are
/// handled internally so managers never know which backend is active.
final class SleepypodCoreClient: SleepypodProtocol, @unchecked Sendable {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var baseURL: URL? {
        guard let ip = UserDefaults.standard.string(forKey: "podIPAddress"), !ip.isEmpty else {
            return nil
        }
        return URL(string: "http://\(ip):3000")
    }

    init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Device Status

    func getDeviceStatus() async throws -> DeviceStatus {
        let results = try await batchQuery([
            BatchCall(procedure: "device.getStatus", input: nil),
            BatchCall(procedure: "health.system", input: nil),
            BatchCall(procedure: "system.wifiStatus", input: nil)
        ])
        let status = try decoder.decode(TRPCDeviceStatus.self, from: results[0].get())
        let health = try decoder.decode(TRPCSystemHealth.self, from: results[1].get())
        let wifi = try? decoder.decode(TRPCWifiStatus.self, from: results[2].get())

        return DeviceStatus(
            left: SideStatus(
                currentTemperatureLevel: fahrenheitToLevel(status.leftSide.currentTemperature),
                currentTemperatureF: Int(status.leftSide.currentTemperature),
                targetTemperatureF: Int(status.leftSide.targetTemperature),
                secondsRemaining: status.leftSide.heatingDuration,
                isOn: status.leftSide.targetLevel != 0,
                isAlarmVibrating: false,
                taps: mapGestures(status.gestures, side: .left)
            ),
            right: SideStatus(
                currentTemperatureLevel: fahrenheitToLevel(status.rightSide.currentTemperature),
                currentTemperatureF: Int(status.rightSide.currentTemperature),
                targetTemperatureF: Int(status.rightSide.targetTemperature),
                secondsRemaining: status.rightSide.heatingDuration,
                isOn: status.rightSide.targetLevel != 0,
                isAlarmVibrating: false,
                taps: mapGestures(status.gestures, side: .right)
            ),
            waterLevel: status.waterLevel,
            isPriming: status.isPriming,
            settings: DeviceHardwareSettings(v: 0, gainLeft: 0, gainRight: 0, ledBrightness: 0),
            coverVersion: status.sensorLabel,
            hubVersion: status.podVersion,
            freeSleep: FreeSleepInfo(
                version: health.status == "ok" ? "core" : "core (degraded)",
                branch: "main"
            ),
            wifiStrength: wifi?.signal ?? 0
        )
    }

    func updateDeviceStatus(_ update: DeviceStatusUpdate) async throws {
        // Map to individual tRPC mutations
        if let left = update.left {
            if let temp = left.targetTemperatureF {
                let _: TRPCSuccess = try await mutate("device.setTemperature", input: [
                    "side": "left",
                    "temperature": temp
                ])
            }
            if let isOn = left.isOn {
                let _: TRPCSuccess = try await mutate("device.setPower", input: [
                    "side": "left",
                    "powered": isOn
                ])
            }
        }
        if let right = update.right {
            if let temp = right.targetTemperatureF {
                let _: TRPCSuccess = try await mutate("device.setTemperature", input: [
                    "side": "right",
                    "temperature": temp
                ])
            }
            if let isOn = right.isOn {
                let _: TRPCSuccess = try await mutate("device.setPower", input: [
                    "side": "right",
                    "powered": isOn
                ])
            }
        }
    }

    // MARK: - Settings

    func getSettings() async throws -> PodSettings {
        let settings: TRPCSettings = try await query("settings.getAll")
        return mapSettingsToFreeFormat(settings)
    }

    func updateSettings(_ settings: PodSettings) async throws -> PodSettings {
        // Update device-level settings
        // primePodDaily and primePodTime must always be sent together — backend requires both.
        let primePodEnabled = settings.primePodDaily.enabled
        let primePodTime = settings.primePodDaily.time.isEmpty ? "14:00" : settings.primePodDaily.time
        var deviceInput: [String: Any] = [:]
        deviceInput["timezone"] = settings.timeZone
        deviceInput["temperatureUnit"] = settings.temperatureFormat == .fahrenheit ? "F" : "C"
        deviceInput["rebootDaily"] = settings.rebootDaily
        deviceInput["rebootTime"] = settings.rebootTime.isEmpty ? "03:00" : settings.rebootTime
        deviceInput["primePodDaily"] = primePodEnabled
        deviceInput["primePodTime"] = primePodTime

        let _: TRPCDeviceSettings = try await mutate("settings.updateDevice", input: deviceInput)

        // Update side settings
        for side in ["left", "right"] {
            let sideSettings = side == "left" ? settings.left : settings.right
            let _: TRPCSideSettings = try await mutate("settings.updateSide", input: [
                "side": side,
                "name": sideSettings.name,
                "awayMode": sideSettings.awayMode
            ])
        }

        return try await getSettings()
    }

    // MARK: - Schedules

    func getSchedules() async throws -> Schedules {
        let leftScheds: TRPCScheduleSet = try await query("schedules.getAll", input: ["side": "left"])
        let rightScheds: TRPCScheduleSet = try await query("schedules.getAll", input: ["side": "right"])
        return Schedules(
            left: mapSchedulesToFreeFormat(leftScheds),
            right: mapSchedulesToFreeFormat(rightScheds)
        )
    }

    func updateSchedules(_ schedules: Schedules, days: Set<DayOfWeek>? = nil) async throws -> Schedules {
        let daysToUpdate = days ?? Set(DayOfWeek.allCases)
        let dayStrings = Set(daysToUpdate.map(\.rawValue))

        var tempDeletes: [Int] = []
        var powerDeletes: [Int] = []
        var alarmDeletes: [Int] = []

        var tempCreates: [[String: Any]] = []
        var powerCreates: [[String: Any]] = []
        var alarmCreates: [[String: Any]] = []

        for side in [Side.left, .right] {
            let existing: TRPCScheduleSet = try await query("schedules.getAll", input: ["side": side.rawValue])
            let sideSchedule = schedules.schedule(for: side)

            // Collect IDs to delete for the days being updated
            tempDeletes.append(contentsOf: existing.temperature.filter { dayStrings.contains($0.dayOfWeek) }.map(\.id))
            powerDeletes.append(contentsOf: existing.power.filter { dayStrings.contains($0.dayOfWeek) }.map(\.id))
            alarmDeletes.append(contentsOf: existing.alarm.filter { dayStrings.contains($0.dayOfWeek) }.map(\.id))

            for day in daysToUpdate {
                let daily = sideSchedule[day]

                for (time, tempF) in daily.temperatures {
                    tempCreates.append([
                        "side": side.rawValue,
                        "dayOfWeek": day.rawValue,
                        "time": time,
                        "temperature": tempF,
                        "enabled": true
                    ])
                }

                if daily.power.enabled {
                    // Skip power schedule if it crosses midnight (core#205)
                    let onMinutes = minutesFromTime(daily.power.on)
                    let offMinutes = minutesFromTime(daily.power.off)
                    if let on = onMinutes, let off = offMinutes, on < off {
                        powerCreates.append([
                            "side": side.rawValue,
                            "dayOfWeek": day.rawValue,
                            "onTime": daily.power.on,
                            "offTime": daily.power.off,
                            "onTemperature": daily.power.onTemperature,
                            "enabled": true
                        ])
                    }
                }

                if daily.alarm.enabled {
                    alarmCreates.append([
                        "side": side.rawValue,
                        "dayOfWeek": day.rawValue,
                        "time": daily.alarm.time,
                        "vibrationIntensity": daily.alarm.vibrationIntensity,
                        "vibrationPattern": daily.alarm.vibrationPattern.rawValue,
                        "duration": daily.alarm.duration,
                        "alarmTemperature": daily.alarm.alarmTemperature,
                        "enabled": true
                    ])
                }
            }
        }

        // Server caps each delete/create array at max(100) per call. Chunk so no
        // single array exceeds that limit; worst case for an "apply to all 7 days"
        // with an AI curve is ~3 chunks, still far fewer round trips than the
        // old N+1 per-schedule pattern.
        let chunks = max(
            1,
            (tempDeletes.count + 99) / 100,
            (powerDeletes.count + 99) / 100,
            (alarmDeletes.count + 99) / 100,
            (tempCreates.count + 99) / 100,
            (powerCreates.count + 99) / 100,
            (alarmCreates.count + 99) / 100
        )

        func slice<T>(_ arr: [T], chunk: Int) -> [T] {
            let start = chunk * 100
            guard start < arr.count else { return [] }
            return Array(arr[start..<min(start + 100, arr.count)])
        }

        for i in 0..<chunks {
            let batchInput: [String: Any] = [
                "deletes": [
                    "temperature": slice(tempDeletes, chunk: i),
                    "power": slice(powerDeletes, chunk: i),
                    "alarm": slice(alarmDeletes, chunk: i)
                ],
                "creates": [
                    "temperature": slice(tempCreates, chunk: i),
                    "power": slice(powerCreates, chunk: i),
                    "alarm": slice(alarmCreates, chunk: i)
                ],
                "updates": [
                    "temperature": [] as [Any],
                    "power": [] as [Any],
                    "alarm": [] as [Any]
                ]
            ]
            let _: TRPCSuccess = try await mutate("schedules.batchUpdate", input: batchInput)
        }

        return try await getSchedules()
    }

    // MARK: - Server Status

    func getServerStatus() async throws -> ServerStatus {
        let results = try await batchQuery([
            BatchCall(procedure: "health.system", input: nil),
            BatchCall(procedure: "health.scheduler", input: nil),
            BatchCall(procedure: "health.hardware", input: nil),
            BatchCall(procedure: "health.dacMonitor", input: nil),
            BatchCall(procedure: "biometrics.getProcessingStatus", input: nil),
            BatchCall(procedure: "system.wifiStatus", input: nil)
        ])
        let health = try decoder.decode(TRPCSystemHealth.self, from: results[0].get())
        let scheduler = try decoder.decode(TRPCSchedulerHealth.self, from: results[1].get())

        // Additional health endpoints are non-critical — tolerate per-call failures
        let hardware = tryDecode(TRPCHardwareHealth.self, from: results[2])
        let dacMonitor = tryDecode(TRPCDacMonitor.self, from: results[3])
        let bioProcessing = tryDecode(TRPCBiometricsProcessing.self, from: results[4])
        let wifi = tryDecode(TRPCWifiStatus.self, from: results[5])

        func info(_ name: String, status: ServiceStatus, desc: String, msg: String = "OK") -> StatusInfo {
            StatusInfo(name: name, status: status, description: desc, message: msg)
        }

        let dbStatus: ServiceStatus = health.database.status == "ok" ? .healthy : .failed
        let schedStatus: ServiceStatus = scheduler.healthy ? .healthy : .failed

        // Hardware status from real endpoints
        let hwStatus: ServiceStatus = hardware?.status == "ok" ? .healthy : (hardware != nil ? .failed : .healthy)
        let hwLatency = hardware.map { String(format: "%.1fms", $0.latencyMs ?? 0) } ?? "OK"

        let dacStatus: ServiceStatus = dacMonitor?.status == "running" ? .healthy : (dacMonitor != nil ? .failed : .healthy)
        let dacMsg = dacMonitor.map { "\($0.status)\($0.gesturesSupported == true ? " · gestures" : "")" } ?? "OK"

        // Biometrics processing
        let bioStatus: ServiceStatus = bioProcessing?.iosProcessingActive == true ? .started : .healthy
        let bioMsg = bioProcessing.map { $0.iosProcessingActive ? "Processing active" : "Idle" } ?? "OK"

        return ServerStatus(
            alarmSchedule: info("Alarm Schedule", status: schedStatus, desc: "Wake-up alarm scheduler", msg: "\(scheduler.jobCounts.alarm) alarms"),
            database: info("Database", status: dbStatus, desc: "SQLite database", msg: health.database.error ?? "\(String(format: "%.1fms", health.database.latencyMs ?? 0)) latency"),
            express: info("Sleepypod Core", status: .healthy, desc: "API and hardware bridge"),
            podSocket: info("Hardware Socket", status: hwStatus, desc: "DAC communication", msg: hwLatency),
            podSocketMonitor: info("DAC Monitor", status: dacStatus, desc: "Hardware watchdog", msg: dacMsg),
            jobs: info("Job Scheduler", status: schedStatus, desc: "Background task runner", msg: "Jobs: \(scheduler.jobCounts.total)"),
            logger: info("Wifi", status: wifi?.connected == true ? .healthy : .failed,
                         desc: wifi?.ssid ?? "Wireless connection",
                         msg: wifi.map { $0.connected ? "\($0.signal ?? 0)% signal" : "Disconnected" } ?? "Unknown"),
            powerSchedule: info("Power Schedule", status: schedStatus, desc: "Auto on/off scheduler", msg: "\(scheduler.jobCounts.powerOn + scheduler.jobCounts.powerOff) power jobs"),
            primeSchedule: info("Prime Schedule", status: schedStatus, desc: "Daily prime scheduler", msg: "\(scheduler.jobCounts.prime) prime jobs"),
            rebootSchedule: info("Reboot Schedule", status: schedStatus, desc: "Daily reboot scheduler", msg: "\(scheduler.jobCounts.reboot) reboot jobs"),
            systemDate: info("Biometrics", status: bioStatus, desc: "Sleep data processing", msg: bioMsg),
            temperatureSchedule: info("Temperature Schedule", status: schedStatus, desc: "Temperature curve scheduler", msg: "\(scheduler.jobCounts.temperature) temp jobs")
        )
    }

    // MARK: - Services

    func getServices() async throws -> Services {
        // sleepypod-core doesn't have a services endpoint yet — return unknown state
        let unknown = StatusInfo(name: "unknown", status: .notStarted, description: "Not available", message: "No API endpoint")
        return Services(
            biometrics: Biometrics(
                enabled: false,
                jobs: BiometricsJobs(
                    analyzeSleepLeft: unknown,
                    analyzeSleepRight: unknown,
                    installation: unknown,
                    stream: unknown,
                    calibrateLeft: unknown,
                    calibrateRight: unknown
                )
            ),
            sentryLogging: SentryLogging(enabled: false)
        )
    }

    func updateServices(_ services: Services) async throws -> Services {
        // No-op for sleepypod-core — biometrics are managed via systemd
        return services
    }

    // MARK: - Log Sources

    func getLogSources() async throws -> [LogSource] {
        struct LogSourcesResponse: Decodable {
            let sources: [LogSource]
        }
        let response: LogSourcesResponse = try await query("system.getLogSources")
        return response.sources
    }

    // MARK: - Metrics

    func getSleepRecords(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [SleepRecord] {
        var input: [String: Any] = [:]
        input["side"] = (side ?? .left).rawValue
        var dateKeys: [String] = []
        if let start { input["startDate"] = ISO8601DateFormatter().string(from: start); dateKeys.append("startDate") }
        if let end { input["endDate"] = ISO8601DateFormatter().string(from: end); dateKeys.append("endDate") }
        return try await query("biometrics.getSleepRecords", input: input, dateKeys: dateKeys)
    }

    func getVitals(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [VitalsRecord] {
        var input: [String: Any] = [:]
        input["side"] = (side ?? .left).rawValue
        var dateKeys: [String] = []
        if let start { input["startDate"] = ISO8601DateFormatter().string(from: start); dateKeys.append("startDate") }
        if let end { input["endDate"] = ISO8601DateFormatter().string(from: end); dateKeys.append("endDate") }
        return try await query("biometrics.getVitals", input: input, dateKeys: dateKeys)
    }

    func getVitalsSummary(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> VitalsSummary {
        let fmt = ISO8601DateFormatter()
        var input: [String: Any] = [:]
        input["side"] = (side ?? .left).rawValue
        let resolvedEnd = end ?? Date()
        let resolvedStart = start ?? Calendar.current.date(byAdding: .day, value: -7, to: resolvedEnd)!
        input["startDate"] = fmt.string(from: resolvedStart)
        input["endDate"] = fmt.string(from: resolvedEnd)
        let result: VitalsSummary? = try await query("biometrics.getVitalsSummary", input: input, dateKeys: ["startDate", "endDate"])
        return result ?? VitalsSummary(avgHeartRate: nil, minHeartRate: nil, maxHeartRate: nil, avgHRV: nil, avgBreathingRate: nil)
    }

    func getMovement(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [MovementRecord] {
        var input: [String: Any] = [:]
        input["side"] = (side ?? .left).rawValue
        var dateKeys: [String] = []
        if let start { input["startDate"] = ISO8601DateFormatter().string(from: start); dateKeys.append("startDate") }
        if let end { input["endDate"] = ISO8601DateFormatter().string(from: end); dateKeys.append("endDate") }
        return try await query("biometrics.getMovement", input: input, dateKeys: dateKeys)
    }

    // MARK: - Actions

    func triggerAlarm(_ alarm: AlarmJob) async throws {
        let _: TRPCSuccess = try await mutate("device.setAlarm", input: [
            "side": alarm.side.rawValue,
            "vibrationIntensity": alarm.vibrationIntensity,
            "vibrationPattern": alarm.vibrationPattern.rawValue,
            "duration": alarm.duration
        ])
    }

    func clearAlarm(side: Side) async throws {
        let _: TRPCSuccess = try await mutate("device.clearAlarm", input: [
            "side": side.rawValue
        ])
    }

    func getCalibrationStatus(side: Side) async throws -> CalibrationStatus {
        try await query("calibration.getStatus", input: ["side": side.rawValue])
    }

    func triggerCalibration(side: Side, sensorType: String) async throws -> CalibrationTriggerResponse {
        try await mutate("calibration.triggerCalibration", input: ["side": side.rawValue, "sensorType": sensorType])
    }

    func triggerFullCalibration() async throws -> CalibrationTriggerResponse {
        try await mutate("calibration.triggerFullCalibration", input: [:] as [String: String])
    }

    // MARK: - Beta Features (PR #193)

    func getVersion() async throws -> SystemVersion {
        try await query("system.getVersion")
    }

    func snoozeAlarm(side: Side, duration: Int = 300) async throws -> SnoozeResponse {
        try await mutate("device.snoozeAlarm", input: [
            "side": side.rawValue,
            "duration": duration
        ])
    }

    func getWaterLevelLatest() async throws -> WaterLevelReading? {
        try await query("waterLevel.getLatest")
    }

    func getWaterLevelTrend(hours: Int = 24) async throws -> WaterLevelTrend {
        try await query("waterLevel.getTrend", input: ["hours": hours])
    }

    func getAmbientLightLatest() async throws -> AmbientLightReading? {
        try await query("environment.getLatestAmbientLight")
    }

    func getBedTempHistory(start: Date, end: Date, limit: Int, unit: String) async throws -> [BedTempReading] {
        let fmt = ISO8601DateFormatter()
        let input: [String: Any] = [
            "startDate": fmt.string(from: start),
            "endDate": fmt.string(from: end),
            "limit": limit,
            "unit": unit
        ]
        return try await query("environment.getBedTemp", input: input, dateKeys: ["startDate", "endDate"])
    }

    func updateSleepRecord(id: Int, enteredBedAt: Date?, leftBedAt: Date?) async throws {
        var input: [String: Any] = ["id": id]
        let fmt = ISO8601DateFormatter()
        if let d = enteredBedAt { input["enteredBedAt"] = fmt.string(from: d) }
        if let d = leftBedAt { input["leftBedAt"] = fmt.string(from: d) }
        var dateKeys: [String] = []
        if enteredBedAt != nil { dateKeys.append("enteredBedAt") }
        if leftBedAt != nil { dateKeys.append("leftBedAt") }
        // Use mutation — the endpoint is biometrics.updateSleepRecord
        let _: SleepRecord = try await mutate("biometrics.updateSleepRecord", input: input)
    }

    func deleteSleepRecord(id: Int) async throws {
        let _: TRPCSuccess = try await mutate("biometrics.deleteSleepRecord", input: ["id": id])
    }

    func dismissPrimeNotification() async throws {
        let _: TRPCSuccess = try await mutate("device.dismissPrimeNotification", input: [:] as [String: String])
    }

    func startRunOnce(side: Side, setPoints: [RunOnceSetPoint], wakeTime: String) async throws -> RunOnceStartResponse {
        let input: [String: Any] = [
            "side": side.rawValue,
            "setPoints": setPoints.map { ["time": $0.time, "temperature": $0.temperature] as [String: Any] },
            "wakeTime": wakeTime
        ]
        return try await mutate("runOnce.start", input: input)
    }

    func getActiveRunOnce(side: Side) async throws -> RunOnceSession? {
        try await query("runOnce.getActive", input: ["side": side.rawValue])
    }

    func cancelRunOnce(side: Side) async throws {
        let _: TRPCSuccess = try await mutate("runOnce.cancel", input: ["side": side.rawValue])
    }

    func getDiskUsage() async throws -> DiskUsage {
        try await query("system.getDiskUsage")
    }

    func getFileCount() async throws -> FileCount {
        try await query("biometrics.getFileCount")
    }

    func setInternetAccess(blocked: Bool) async throws {
        let _: TRPCInternetStatus = try await mutate("system.setInternetAccess", input: ["blocked": blocked])
    }

    func reboot() async throws {
        // sleepypod-core uses system.triggerUpdate for restarts
        // For a full reboot, there's no direct endpoint — this is a best-effort
        let _: TRPCSuccess = try await mutate("device.startPriming", input: [:] as [String: String])
        // TODO: Add a reboot procedure to the system router
    }

    // MARK: - tRPC Transport

    /// tRPC query — GET /api/trpc/{procedure}?input={json}
    /// dateKeys: keys in `input` that should be annotated as Date in superjson meta
    private func query<T: Decodable>(_ procedure: String, input: [String: Any]? = nil, dateKeys: [String] = []) async throws -> T {
        guard let base = baseURL else { throw APIError.noBaseURL }

        var urlString = "\(base)/api/trpc/\(procedure)"
        // tRPC v11 requires input param even for no-input queries
        let inputJSON: String
        if let input, !input.isEmpty {
            let inputData = try JSONSerialization.data(withJSONObject: input)
            inputJSON = String(data: inputData, encoding: .utf8) ?? "{}"
        } else {
            inputJSON = "{}"
        }

        // Build superjson envelope with optional meta for Date fields
        var wrapped: String
        if !dateKeys.isEmpty {
            var values: [String: [String]] = [:]
            for key in dateKeys { values[key] = ["Date"] }
            let metaData = try JSONSerialization.data(withJSONObject: ["values": values])
            let metaJSON = String(data: metaData, encoding: .utf8) ?? "{}"
            wrapped = "{\"json\":\(inputJSON),\"meta\":\(metaJSON)}"
        } else {
            wrapped = "{\"json\":\(inputJSON)}"
        }
        let encoded = wrapped.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? wrapped
        urlString += "?input=\(encoded)"

        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        let (data, response) = try await performRequest(request)
        try validateResponse(response)
        return try decodeTRPCResult(data)
    }

    /// tRPC mutation — POST /api/trpc/{procedure} with body {"json": input}
    private func mutate<T: Decodable>(_ procedure: String, input: [String: Any]) async throws -> T {
        guard let base = baseURL else { throw APIError.noBaseURL }
        guard let url = URL(string: "\(base)/api/trpc/\(procedure)") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let wrapped: [String: Any] = ["json": input]
        request.httpBody = try JSONSerialization.data(withJSONObject: wrapped)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data, procedure: procedure)
        return try decodeTRPCResult(data)
    }

    /// tRPC batch query — coalesces multiple queries into one HTTP request.
    /// Mirrors @trpc/client's httpBatchLink format:
    ///   GET /api/trpc/a,b,c?batch=1&input={"0":{"json":...},"1":{"json":...}}
    /// Response is an array; each slot is either result-wrapped or error-wrapped.
    /// Per-call results come back as re-serialized json payloads so callers decode
    /// heterogeneous types into their own models. Per-call errors surface as .failure.
    private func batchQuery(_ calls: [BatchCall]) async throws -> [Result<Data, Error>] {
        guard let base = baseURL else { throw APIError.noBaseURL }
        guard !calls.isEmpty else { return [] }

        let procedures = calls.map(\.procedure).joined(separator: ",")

        var inputMap: [String: Any] = [:]
        for (i, call) in calls.enumerated() {
            inputMap[String(i)] = ["json": call.input ?? [:]]
        }
        let inputData = try JSONSerialization.data(withJSONObject: inputMap)
        let inputJSON = String(data: inputData, encoding: .utf8) ?? "{}"
        let encoded = inputJSON.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? inputJSON

        let urlString = "\(base)/api/trpc/\(procedures)?batch=1&input=\(encoded)"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        let (data, response) = try await performRequest(request)
        try validateResponse(response)

        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let envelope = parsed as? [Any], envelope.count == calls.count else {
            throw APIError.decodingFailed(NSError(
                domain: "tRPC.batch", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Expected array of \(calls.count) results"]
            ))
        }

        return envelope.map { item in
            guard let obj = item as? [String: Any] else {
                return .failure(APIError.decodingFailed(NSError(domain: "tRPC.batch", code: 1)))
            }
            if let err = obj["error"] as? [String: Any] {
                let msg = (err["json"] as? [String: Any])?["message"] as? String
                    ?? err["message"] as? String
                    ?? "tRPC error"
                return .failure(APIError.serverError(message: msg))
            }
            guard let result = obj["result"] as? [String: Any],
                  let dataObj = result["data"] as? [String: Any],
                  let json = dataObj["json"] else {
                return .failure(APIError.decodingFailed(NSError(domain: "tRPC.batch", code: 2)))
            }
            do {
                let bytes = try JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed])
                return .success(bytes)
            } catch {
                return .failure(error)
            }
        }
    }

    /// Decode a batch slot optionally — used for non-critical calls that may fail.
    private func tryDecode<T: Decodable>(_ type: T.Type, from result: Result<Data, Error>) -> T? {
        guard let data = try? result.get() else { return nil }
        return try? decoder.decode(type, from: data)
    }

    /// Decode tRPC response envelope: {"result": {"data": {"json": T}}}
    private func decodeTRPCResult<T: Decodable>(_ data: Data) throws -> T {
        do {
            let envelope = try decoder.decode(TRPCEnvelope<T>.self, from: data)
            return envelope.result.data.json
        } catch {
            Log.network.error("Decode failed: \(error)")
            throw APIError.decodingFailed(error)
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            Log.network.error("Request failed: \(request.url?.absoluteString ?? "?") — \(error)")
            throw APIError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data? = nil, procedure: String? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: 0)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let tag = procedure ?? httpResponse.url?.absoluteString ?? "?"
            // Surface the tRPC error message so validation failures aren't silent
            let body = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(500) ?? ""
            Log.network.error("HTTP \(httpResponse.statusCode) \(tag) — \(String(body))")
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Mapping Helpers

    private func fahrenheitToLevel(_ tempF: Double) -> Int {
        Int(((tempF - 82.5) / 27.5) * 100)
    }

    private func minutesFromTime(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    private func mapGestures(_ gestures: TRPCGestures?, side: Side) -> TapCounts? {
        guard let g = gestures else { return nil }
        return TapCounts(
            doubleTap: side == .left ? (g.doubleTap?.l ?? 0) : (g.doubleTap?.r ?? 0),
            tripleTap: side == .left ? (g.tripleTap?.l ?? 0) : (g.tripleTap?.r ?? 0),
            quadTap: side == .left ? (g.quadTap?.l ?? 0) : (g.quadTap?.r ?? 0)
        )
    }

    private func mapSettingsToFreeFormat(_ s: TRPCSettings) -> PodSettings {
        let defaultTapConfig = TapConfig.temperature(change: .increment, amount: 2)
        let defaultTaps = TapSettings(doubleTap: defaultTapConfig, tripleTap: defaultTapConfig, quadTap: defaultTapConfig)
        let defaultOverrides = ScheduleOverrides(
            temperatureSchedules: TemperatureScheduleOverride(disabled: false, expiresAt: ""),
            alarm: AlarmOverride(disabled: false, timeOverride: "", expiresAt: "")
        )

        let device = s.device
        let leftSide = s.sides?.left
        let rightSide = s.sides?.right

        func mapSideGestures(_ gestures: [TRPCTapGesture]?) -> TapSettings {
            guard let gestures else { return defaultTaps }
            var taps = defaultTaps
            for g in gestures {
                let config: TapConfig
                if g.actionType == "temperature" {
                    config = .temperature(
                        change: g.temperatureChange == "decrement" ? .decrement : .increment,
                        amount: g.temperatureAmount ?? 2
                    )
                } else {
                    config = .alarm(
                        behavior: g.alarmBehavior == "dismiss" ? .dismiss : .snooze,
                        snoozeDuration: g.alarmSnoozeDuration ?? 300,
                        inactiveAlarmBehavior: g.alarmInactiveBehavior == "power" ? .power : .none
                    )
                }
                switch g.tapType {
                case "doubleTap": taps.doubleTap = config
                case "tripleTap": taps.tripleTap = config
                case "quadTap": taps.quadTap = config
                default: break
                }
            }
            return taps
        }

        return PodSettings(
            id: "1",
            timeZone: device?.timezone ?? TimeZone.current.identifier,
            left: SideSettings(
                name: leftSide?.name ?? "Left",
                awayMode: leftSide?.awayMode ?? false,
                scheduleOverrides: defaultOverrides,
                taps: mapSideGestures(s.gestures?.left)
            ),
            right: SideSettings(
                name: rightSide?.name ?? "Right",
                awayMode: rightSide?.awayMode ?? false,
                scheduleOverrides: defaultOverrides,
                taps: mapSideGestures(s.gestures?.right)
            ),
            primePodDaily: PrimePodDaily(
                enabled: device?.primePodDaily ?? false,
                time: device?.primePodTime ?? "14:00"
            ),
            temperatureFormat: device?.temperatureUnit == "C" ? .celsius : .fahrenheit,
            rebootDaily: device?.rebootDaily ?? false,
            rebootTime: device?.rebootTime ?? "03:00"
        )
    }

    private func mapSchedulesToFreeFormat(_ scheds: TRPCScheduleSet) -> SideSchedule {
        let emptyDaily = DailySchedule(
            temperatures: [:],
            alarm: AlarmSchedule(vibrationIntensity: 50, vibrationPattern: .rise, duration: 30, time: "07:00", enabled: false, alarmTemperature: 80),
            power: PowerSchedule(on: "22:00", off: "07:00", onTemperature: 75, enabled: false)
        )

        var byDay: [String: DailySchedule] = [:]
        for day in DayOfWeek.allCases {
            byDay[day.rawValue] = emptyDaily
        }

        // Fill temperature schedules
        for t in scheds.temperature where t.enabled {
            byDay[t.dayOfWeek, default: emptyDaily].temperatures[t.time] = Int(t.temperature)
        }

        // Fill power schedules (take last one per day)
        for p in scheds.power where p.enabled {
            byDay[p.dayOfWeek, default: emptyDaily].power = PowerSchedule(
                on: p.onTime, off: p.offTime, onTemperature: Int(p.onTemperature), enabled: true
            )
        }

        // Fill alarm schedules (take last one per day)
        for a in scheds.alarm where a.enabled {
            byDay[a.dayOfWeek, default: emptyDaily].alarm = AlarmSchedule(
                vibrationIntensity: a.vibrationIntensity,
                vibrationPattern: VibrationPattern(rawValue: a.vibrationPattern) ?? .rise,
                duration: a.duration,
                time: a.time,
                enabled: true,
                alarmTemperature: Int(a.alarmTemperature)
            )
        }

        return SideSchedule(
            sunday: byDay["sunday"]!,
            monday: byDay["monday"]!,
            tuesday: byDay["tuesday"]!,
            wednesday: byDay["wednesday"]!,
            thursday: byDay["thursday"]!,
            friday: byDay["friday"]!,
            saturday: byDay["saturday"]!
        )
    }
}

// MARK: - tRPC Envelope Types

private struct BatchCall {
    let procedure: String
    let input: [String: Any]?
}

private struct TRPCEnvelope<R: Decodable>: Decodable {
    let result: TRPCResultData<R>
}

private struct TRPCResultData<R: Decodable>: Decodable {
    let data: TRPCJSONWrapper<R>
}

private struct TRPCJSONWrapper<R: Decodable>: Decodable {
    let json: R
}

// MARK: - tRPC Response Types (internal only)

private struct TRPCSuccess: Decodable {
    let success: Bool?
}

private struct TRPCSideStatus: Decodable {
    let currentTemperature: Double
    let targetTemperature: Double
    let currentLevel: Int
    let targetLevel: Int
    let heatingDuration: Int
}

private struct TRPCGesturePair: Decodable {
    let l: Int
    let r: Int
    let s: Int?
}

private struct TRPCGestures: Decodable {
    let doubleTap: TRPCGesturePair?
    let tripleTap: TRPCGesturePair?
    let quadTap: TRPCGesturePair?
}

private struct TRPCDeviceStatus: Decodable {
    let leftSide: TRPCSideStatus
    let rightSide: TRPCSideStatus
    let waterLevel: String
    let isPriming: Bool
    let podVersion: String
    let sensorLabel: String
    let gestures: TRPCGestures?
}

private struct TRPCDeviceSettings: Decodable {
    let timezone: String?
    let temperatureUnit: String?
    let rebootDaily: Bool?
    let rebootTime: String?
    let primePodDaily: Bool?
    let primePodTime: String?
}

private struct TRPCSideSettings: Decodable {
    let side: String?
    let name: String?
    let awayMode: Bool?
}

private struct TRPCTapGesture: Decodable {
    let side: String
    let tapType: String
    let actionType: String
    let temperatureChange: String?
    let temperatureAmount: Int?
    let alarmBehavior: String?
    let alarmSnoozeDuration: Int?
    let alarmInactiveBehavior: String?
}

private struct TRPCSettings: Decodable {
    let device: TRPCDeviceSettings?
    let sides: TRPCSettingsSides?
    let gestures: TRPCSettingsGestures?
}

private struct TRPCSettingsSides: Decodable {
    let left: TRPCSideSettings?
    let right: TRPCSideSettings?
}

private struct TRPCSettingsGestures: Decodable {
    let left: [TRPCTapGesture]?
    let right: [TRPCTapGesture]?
}

private struct TRPCSystemHealth: Decodable {
    let status: String
    let database: TRPCDBHealth
    let scheduler: TRPCSchedulerBrief
}

private struct TRPCDBHealth: Decodable {
    let status: String
    let latencyMs: Double?
    let error: String?
}

private struct TRPCSchedulerBrief: Decodable {
    let enabled: Bool
    let jobCount: Int
}

private struct TRPCSchedulerHealth: Decodable {
    let enabled: Bool
    let jobCounts: TRPCJobCounts
    let healthy: Bool
}

private struct TRPCJobCounts: Decodable {
    let total: Int
    let temperature: Int
    let powerOn: Int
    let powerOff: Int
    let alarm: Int
    let prime: Int
    let reboot: Int
}

private struct TRPCTemperatureSchedule: Decodable {
    let id: Int
    let side: String
    let dayOfWeek: String
    let time: String
    let temperature: Double
    let enabled: Bool
}

private struct TRPCPowerSchedule: Decodable {
    let id: Int
    let side: String
    let dayOfWeek: String
    let onTime: String
    let offTime: String
    let onTemperature: Double
    let enabled: Bool
}

private struct TRPCAlarmSchedule: Decodable {
    let id: Int
    let side: String
    let dayOfWeek: String
    let time: String
    let vibrationIntensity: Int
    let vibrationPattern: String
    let duration: Int
    let alarmTemperature: Double
    let enabled: Bool
}

private struct TRPCScheduleSet: Decodable {
    let temperature: [TRPCTemperatureSchedule]
    let power: [TRPCPowerSchedule]
    let alarm: [TRPCAlarmSchedule]
}

// Disk usage
struct DiskUsage: Decodable, Sendable {
    let totalBytes: Int
    let usedBytes: Int
    let availableBytes: Int
    let usedPercent: Double

    var usedGB: String { String(format: "%.1f", Double(usedBytes) / 1_073_741_824) }
    var totalGB: String { String(format: "%.1f", Double(totalBytes) / 1_073_741_824) }
    var freeGB: String { String(format: "%.1f", Double(availableBytes) / 1_073_741_824) }
}

// File count
struct FileCount: Decodable, Sendable {
    let rawFiles: RawFileCount
    let totalSizeMB: Double

    struct RawFileCount: Decodable, Sendable {
        let left: Int
        let right: Int
    }

    var totalFiles: Int { rawFiles.left + rawFiles.right }
    var sizeDisplay: String { String(format: "%.0f MB", totalSizeMB) }
}

// Calibration
struct CalibrationSensor: Decodable, Sendable {
    let id: Int
    let side: String
    let sensorType: String
    let status: String
    let qualityScore: Double?
    let samplesUsed: Int?
    let errorMessage: String?
}

struct CalibrationStatus: Decodable, Sendable {
    let capacitance: CalibrationSensor?
    let piezo: CalibrationSensor?
    let temperature: CalibrationSensor?

    var sensors: [CalibrationSensor] { [capacitance, piezo, temperature].compactMap { $0 } }
    var healthyCount: Int { sensors.filter { $0.status == "completed" }.count }
}

// New endpoints
private struct TRPCHardwareHealth: Decodable {
    let status: String
    let socketPath: String?
    let latencyMs: Double?
}

private struct TRPCDacMonitor: Decodable {
    let status: String
    let podVersion: String?
    let gesturesSupported: Bool?
}

private struct TRPCBiometricsProcessing: Decodable {
    let iosProcessingActive: Bool
    let connectedSince: String?
}

private struct TRPCInternetStatus: Decodable {
    let blocked: Bool
}

private struct TRPCWifiStatus: Decodable {
    let connected: Bool
    let ssid: String?
    let signal: Int?
}
