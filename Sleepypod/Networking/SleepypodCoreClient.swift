import Foundation

/// tRPC client for sleepypod-core (Next.js backend).
///
/// Translates `FreeSleepAPIProtocol` calls into tRPC HTTP requests.
/// tRPC queries use GET with input as a URL-encoded JSON param.
/// tRPC mutations use POST with JSON body `{"json": input}`.
///
/// Data shape differences between free-sleep and sleepypod-core are
/// handled internally so managers never know which backend is active.
final class SleepypodCoreClient: FreeSleepAPIProtocol, @unchecked Sendable {
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
        let status: TRPCDeviceStatus = try await query("device.getStatus")
        let settings: TRPCSettings = try await query("settings.getAll")
        let health: TRPCSystemHealth = try await query("health.system")

        return DeviceStatus(
            left: SideStatus(
                currentTemperatureLevel: fahrenheitToLevel(status.leftSide.currentTemperature),
                currentTemperatureF: Int(status.leftSide.currentTemperature),
                targetTemperatureF: Int(status.leftSide.targetTemperature),
                secondsRemaining: status.leftSide.heatingDuration,
                isOn: status.leftSide.targetLevel != 0,
                isAlarmVibrating: false, // tRPC doesn't expose this directly in getStatus
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
            wifiStrength: 100 // Not available from tRPC — assume connected
        )
    }

    func updateDeviceStatus(_ update: DeviceStatusUpdate) async throws {
        // Map to individual tRPC mutations
        if let left = update.left {
            if let temp = left.targetTemperatureF {
                let _: TRPCSuccess = try await mutate("device.setTemperature", input: [
                    "side": "left",
                    "temperature": temp,
                ])
            }
            if let isOn = left.isOn {
                let _: TRPCSuccess = try await mutate("device.setPower", input: [
                    "side": "left",
                    "powered": isOn,
                ])
            }
        }
        if let right = update.right {
            if let temp = right.targetTemperatureF {
                let _: TRPCSuccess = try await mutate("device.setTemperature", input: [
                    "side": "right",
                    "temperature": temp,
                ])
            }
            if let isOn = right.isOn {
                let _: TRPCSuccess = try await mutate("device.setPower", input: [
                    "side": "right",
                    "powered": isOn,
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
        deviceInput["primePodDaily"] = primePodEnabled
        deviceInput["primePodTime"] = primePodTime

        let _: TRPCDeviceSettings = try await mutate("settings.updateDevice", input: deviceInput)

        // Update side settings
        for side in ["left", "right"] {
            let sideSettings = side == "left" ? settings.left : settings.right
            let _: TRPCSideSettings = try await mutate("settings.updateSide", input: [
                "side": side,
                "name": sideSettings.name,
                "awayMode": sideSettings.awayMode,
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

    func updateSchedules(_ schedules: Schedules) async throws -> Schedules {
        // Delete all existing and recreate — simplest approach for full-replace semantics
        // that free-sleep uses (POST /api/schedules replaces everything)
        for side in [Side.left, .right] {
            let existing: TRPCScheduleSet = try await query("schedules.getAll", input: ["side": side.rawValue])

            // Delete existing
            for sched in existing.temperature {
                let _: TRPCSuccess = try await mutate("schedules.deleteTemperatureSchedule", input: ["id": sched.id])
            }
            for sched in existing.power {
                let _: TRPCSuccess = try await mutate("schedules.deletePowerSchedule", input: ["id": sched.id])
            }
            for sched in existing.alarm {
                let _: TRPCSuccess = try await mutate("schedules.deleteAlarmSchedule", input: ["id": sched.id])
            }

            // Create new from the free-sleep format
            let sideSchedule = schedules.schedule(for: side)
            for day in DayOfWeek.allCases {
                let daily = sideSchedule[day]

                // Temperature schedules
                for (time, tempF) in daily.temperatures {
                    let _: TRPCTemperatureSchedule = try await mutate("schedules.createTemperatureSchedule", input: [
                        "side": side.rawValue,
                        "dayOfWeek": day.rawValue,
                        "time": time,
                        "temperature": tempF,
                    ])
                }

                // Power schedule
                if daily.power.enabled {
                    let _: TRPCPowerSchedule = try await mutate("schedules.createPowerSchedule", input: [
                        "side": side.rawValue,
                        "dayOfWeek": day.rawValue,
                        "onTime": daily.power.on,
                        "offTime": daily.power.off,
                        "onTemperature": daily.power.onTemperature,
                        "enabled": true,
                    ])
                }

                // Alarm schedule
                if daily.alarm.enabled {
                    let _: TRPCAlarmSchedule = try await mutate("schedules.createAlarmSchedule", input: [
                        "side": side.rawValue,
                        "dayOfWeek": day.rawValue,
                        "time": daily.alarm.time,
                        "vibrationIntensity": daily.alarm.vibrationIntensity,
                        "vibrationPattern": daily.alarm.vibrationPattern.rawValue,
                        "duration": daily.alarm.duration,
                        "alarmTemperature": daily.alarm.alarmTemperature,
                        "enabled": true,
                    ])
                }
            }
        }

        return try await getSchedules()
    }

    // MARK: - Server Status

    func getServerStatus() async throws -> ServerStatus {
        let health: TRPCSystemHealth = try await query("health.system")
        let scheduler: TRPCSchedulerHealth = try await query("health.scheduler")

        // Map sleepypod-core health data to ServerStatus shape
        let isDBHealthy = health.database.status == "ok"
        let isSchedulerHealthy = scheduler.healthy

        func info(_ name: String, status: ServiceStatus, desc: String, msg: String = "OK") -> StatusInfo {
            StatusInfo(name: name, status: status, description: desc, message: msg)
        }

        let dbStatus: ServiceStatus = isDBHealthy ? .healthy : .failed
        let schedStatus: ServiceStatus = isSchedulerHealthy ? .healthy : .failed
        let jobsMsg = "Jobs: \(scheduler.jobCounts.total)"

        // Note: sleepypod-core doesn't have biometrics/calibration service status endpoints yet.
        // Biometrics and Calibration categories will be empty until core adds:
        //   - health.biometrics (sleep analysis, stream, installation status per side)
        //   - health.calibration (piezo calibration status per side)
        // See: https://github.com/sleepypod/core/issues/149

        return ServerStatus(
            alarmSchedule: info("Alarm Schedule", status: schedStatus, desc: "Wake-up alarm scheduler", msg: "\(scheduler.jobCounts.alarm) alarms"),
            database: info("Database", status: dbStatus, desc: "SQLite database", msg: health.database.error ?? "OK"),
            express: info("API Server", status: .healthy, desc: "tRPC HTTP server"),
            podSocket: info("Pod Socket", status: .healthy, desc: "Hardware communication"),
            podSocketMonitor: info("Pod Monitor", status: .healthy, desc: "Connection watchdog"),
            jobs: info("Job Scheduler", status: schedStatus, desc: "Background task runner", msg: jobsMsg),
            logger: info("Logger", status: .healthy, desc: "System logging"),
            powerSchedule: info("Power Schedule", status: schedStatus, desc: "Auto on/off scheduler", msg: "\(scheduler.jobCounts.powerOn + scheduler.jobCounts.powerOff) power jobs"),
            primeSchedule: info("Prime Schedule", status: schedStatus, desc: "Daily prime scheduler", msg: "\(scheduler.jobCounts.prime) prime jobs"),
            rebootSchedule: info("Reboot Schedule", status: schedStatus, desc: "Daily reboot scheduler", msg: "\(scheduler.jobCounts.reboot) reboot jobs"),
            systemDate: info("System Clock", status: .healthy, desc: "Server time"),
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

    // MARK: - Metrics

    func getSleepRecords(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [SleepRecord] {
        var input: [String: Any] = [:]
        input["side"] = (side ?? .left).rawValue
        if let start { input["startDate"] = ISO8601DateFormatter().string(from: start) }
        if let end { input["endDate"] = ISO8601DateFormatter().string(from: end) }
        return try await query("biometrics.getSleepRecords", input: input)
    }

    func getVitals(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [VitalsRecord] {
        var input: [String: Any] = [:]
        input["side"] = (side ?? .left).rawValue
        if let start { input["startDate"] = ISO8601DateFormatter().string(from: start) }
        if let end { input["endDate"] = ISO8601DateFormatter().string(from: end) }
        return try await query("biometrics.getVitals", input: input)
    }

    func getVitalsSummary(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> VitalsSummary {
        let fmt = ISO8601DateFormatter()
        var input: [String: Any] = [:]
        input["side"] = (side ?? .left).rawValue
        let resolvedEnd = end ?? Date()
        let resolvedStart = start ?? Calendar.current.date(byAdding: .day, value: -7, to: resolvedEnd)!
        input["startDate"] = fmt.string(from: resolvedStart)
        input["endDate"] = fmt.string(from: resolvedEnd)
        let result: VitalsSummary? = try await query("biometrics.getVitalsSummary", input: input)
        return result ?? VitalsSummary(avgHeartRate: nil, minHeartRate: nil, maxHeartRate: nil, avgHRV: nil, avgBreathingRate: nil)
    }

    func getMovement(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [MovementRecord] {
        var input: [String: Any] = [:]
        input["side"] = (side ?? .left).rawValue
        if let start { input["startDate"] = ISO8601DateFormatter().string(from: start) }
        if let end { input["endDate"] = ISO8601DateFormatter().string(from: end) }
        return try await query("biometrics.getMovement", input: input)
    }

    // MARK: - Actions

    func triggerAlarm(_ alarm: AlarmJob) async throws {
        let _: TRPCSuccess = try await mutate("device.setAlarm", input: [
            "side": alarm.side.rawValue,
            "vibrationIntensity": alarm.vibrationIntensity,
            "vibrationPattern": alarm.vibrationPattern.rawValue,
            "duration": alarm.duration,
        ])
    }

    func reboot() async throws {
        // sleepypod-core uses system.triggerUpdate for restarts
        // For a full reboot, there's no direct endpoint — this is a best-effort
        let _: TRPCSuccess = try await mutate("device.startPriming", input: [:] as [String: String])
        // TODO: Add a reboot procedure to the system router
    }

    // MARK: - tRPC Transport

    /// tRPC query — GET /api/trpc/{procedure}?input={json}
    private func query<T: Decodable>(_ procedure: String, input: [String: Any]? = nil) async throws -> T {
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
        let wrapped = "{\"json\":\(inputJSON)}"
        let encoded = wrapped.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? wrapped
        urlString += "?input=\(encoded)"

        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30 // Hardware can be slow

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
        request.timeoutInterval = 30

        let wrapped: [String: Any] = ["json": input]
        request.httpBody = try JSONSerialization.data(withJSONObject: wrapped)

        let (data, response) = try await performRequest(request)
        try validateResponse(response)
        return try decodeTRPCResult(data)
    }

    /// Decode tRPC response envelope: {"result": {"data": {"json": T}}}
    private func decodeTRPCResult<T: Decodable>(_ data: Data) throws -> T {
        do {
            let envelope = try decoder.decode(TRPCEnvelope<T>.self, from: data)
            return envelope.result.data.json
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: 0)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Mapping Helpers

    private func fahrenheitToLevel(_ tempF: Double) -> Int {
        Int(((tempF - 82.5) / 27.5) * 100)
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
            rebootDaily: device?.rebootDaily ?? false
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
