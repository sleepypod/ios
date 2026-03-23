import Foundation

/// In-memory mock implementation of `SleepypodProtocol` for demo mode.
/// All data is canned but realistic, and mutable state enables optimistic UI updates.
/// Mutable state is only accessed from `async` calls originating on `@MainActor` managers,
/// so no additional synchronization is required.
final class MockClient: SleepypodProtocol, @unchecked Sendable {

    // MARK: - Mutable State

    private var leftOn = true
    private var rightOn = true
    private var leftTargetF = 72
    private var rightTargetF = 68
    private var leftCurrentF = 74
    private var rightCurrentF = 70

    private var settings: PodSettings
    private var schedules: Schedules

    // MARK: - Init

    init() {
        let defaultTaps = TapSettings(
            doubleTap: .temperature(change: .decrement, amount: 2),
            tripleTap: .temperature(change: .increment, amount: 2),
            quadTap: .alarm(behavior: .snooze, snoozeDuration: 300, inactiveAlarmBehavior: .power)
        )
        let defaultOverrides = ScheduleOverrides(
            temperatureSchedules: TemperatureScheduleOverride(disabled: false, expiresAt: ""),
            alarm: AlarmOverride(disabled: false, timeOverride: "", expiresAt: "")
        )

        settings = PodSettings(
            id: "demo-pod-001",
            timeZone: "America/Los_Angeles",
            left: SideSettings(name: "Left", awayMode: false, scheduleOverrides: defaultOverrides, taps: defaultTaps),
            right: SideSettings(name: "Right", awayMode: false, scheduleOverrides: defaultOverrides, taps: defaultTaps),
            primePodDaily: PrimePodDaily(enabled: true, time: "14:00"),
            temperatureFormat: .fahrenheit,
            rebootDaily: false,
            rebootTime: "03:00"
        )

        let defaultDaily = DailySchedule(
            temperatures: ["22:00": 70, "23:30": 68, "02:00": 66, "05:00": 70],
            alarm: AlarmSchedule(vibrationIntensity: 60, vibrationPattern: .rise, duration: 300, time: "07:00", enabled: true, alarmTemperature: 78),
            power: PowerSchedule(on: "21:30", off: "08:00", onTemperature: 72, enabled: true)
        )
        let sideSchedule = SideSchedule(
            sunday: defaultDaily, monday: defaultDaily, tuesday: defaultDaily,
            wednesday: defaultDaily, thursday: defaultDaily, friday: defaultDaily, saturday: defaultDaily
        )
        schedules = Schedules(left: sideSchedule, right: sideSchedule)
    }

    // MARK: - Device Status

    func getDeviceStatus() async throws -> DeviceStatus {
        DeviceStatus(
            left: SideStatus(
                currentTemperatureLevel: 0,
                currentTemperatureF: leftCurrentF,
                targetTemperatureF: leftTargetF,
                secondsRemaining: 0,
                isOn: leftOn,
                isAlarmVibrating: false,
                taps: TapCounts(doubleTap: 12, tripleTap: 3, quadTap: 1)
            ),
            right: SideStatus(
                currentTemperatureLevel: 0,
                currentTemperatureF: rightCurrentF,
                targetTemperatureF: rightTargetF,
                secondsRemaining: 0,
                isOn: rightOn,
                isAlarmVibrating: false,
                taps: TapCounts(doubleTap: 8, tripleTap: 2, quadTap: 0)
            ),
            waterLevel: "ok",
            isPriming: false,
            settings: DeviceHardwareSettings(v: 2, gainLeft: 1.0, gainRight: 1.0, ledBrightness: 60),
            coverVersion: "v3.2.1",
            hubVersion: "v1.8.0",
            freeSleep: FreeSleepInfo(version: "demo", branch: "demo"),
            wifiStrength: 82
        )
    }

    func updateDeviceStatus(_ update: DeviceStatusUpdate) async throws {
        if let left = update.left {
            if let temp = left.targetTemperatureF { leftTargetF = temp }
            if let isOn = left.isOn { leftOn = isOn }
        }
        if let right = update.right {
            if let temp = right.targetTemperatureF { rightTargetF = temp }
            if let isOn = right.isOn { rightOn = isOn }
        }
        // Simulate current temp drifting toward target
        leftCurrentF = leftOn ? leftTargetF + 2 : leftCurrentF
        rightCurrentF = rightOn ? rightTargetF + 2 : rightCurrentF
    }

    // MARK: - Settings

    func getSettings() async throws -> PodSettings {
        settings
    }

    func updateSettings(_ newSettings: PodSettings) async throws -> PodSettings {
        settings = newSettings
        return settings
    }

    // MARK: - Schedules

    func getSchedules() async throws -> Schedules {
        schedules
    }

    func updateSchedules(_ newSchedules: Schedules, days: Set<DayOfWeek>? = nil) async throws -> Schedules {
        if let days {
            for day in days {
                schedules.left[day] = newSchedules.left[day]
                schedules.right[day] = newSchedules.right[day]
            }
        } else {
            schedules = newSchedules
        }
        return schedules
    }

    // MARK: - Server Status

    func getServerStatus() async throws -> ServerStatus {
        let now = ISO8601DateFormatter().string(from: Date())
        func info(_ name: String, desc: String, msg: String = "OK") -> StatusInfo {
            StatusInfo(name: name, status: .healthy, description: desc, message: msg, timestamp: now)
        }
        return ServerStatus(
            alarmSchedule: info("Alarm Schedule", desc: "Wake-up alarm scheduler", msg: "2 alarms"),
            database: info("Database", desc: "SQLite database", msg: "0.3ms latency"),
            express: info("Sleepypod Core", desc: "API and hardware bridge"),
            podSocket: info("Hardware Socket", desc: "DAC communication", msg: "1.2ms"),
            podSocketMonitor: info("DAC Monitor", desc: "Hardware watchdog", msg: "running"),
            jobs: info("Job Scheduler", desc: "Background task runner", msg: "Jobs: 14"),
            logger: info("Wifi", desc: "DemoNetwork", msg: "82% signal"),
            powerSchedule: info("Power Schedule", desc: "Auto on/off scheduler", msg: "2 power jobs"),
            primeSchedule: info("Prime Schedule", desc: "Daily prime scheduler", msg: "1 prime jobs"),
            rebootSchedule: info("Reboot Schedule", desc: "Daily reboot scheduler", msg: "0 reboot jobs"),
            systemDate: info("Biometrics", desc: "Sleep data processing", msg: "Idle"),
            temperatureSchedule: info("Temperature Schedule", desc: "Temperature curve scheduler", msg: "8 temp jobs")
        )
    }

    // MARK: - Services

    func getServices() async throws -> Services {
        let unknown = StatusInfo(name: "unknown", status: .healthy, description: "Demo", message: "OK")
        return Services(
            biometrics: Biometrics(
                enabled: true,
                jobs: BiometricsJobs(
                    analyzeSleepLeft: unknown, analyzeSleepRight: unknown,
                    installation: unknown, stream: unknown,
                    calibrateLeft: unknown, calibrateRight: unknown
                )
            ),
            sentryLogging: SentryLogging(enabled: false)
        )
    }

    func updateServices(_ services: Services) async throws -> Services {
        services
    }

    // MARK: - Log Sources

    func getLogSources() async throws -> [LogSource] {
        [
            LogSource(unit: "sleepypod.service", name: "Core", active: true),
            LogSource(unit: "sleepypod-piezo-processor.service", name: "Piezo Processor", active: true),
            LogSource(unit: "sleepypod-sleep-detector.service", name: "Sleep Detector", active: true),
            LogSource(unit: "sleepypod-environment-monitor.service", name: "Environment Monitor", active: true),
        ]
    }

    // MARK: - Sleep Records

    func getSleepRecords(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [SleepRecord] {
        let cal = Calendar.current
        let now = Date()
        var records: [SleepRecord] = []

        // Sleep durations and bedtimes with natural variation
        let durations: [(hours: Int, minutes: Int)] = [
            (7, 42), (6, 55), (7, 18), (8, 5), (7, 30), (6, 48), (7, 55)
        ]
        let bedtimeHours = [22, 23, 22, 23, 22, 23, 22]       // 10 or 11 PM
        let bedtimeMinutes = [45, 10, 30, 0, 15, 20, 50]

        for i in 0..<7 {
            let daysAgo = 7 - i
            guard var bedtime = cal.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            bedtime = cal.date(bySettingHour: bedtimeHours[i], minute: bedtimeMinutes[i], second: 0, of: bedtime) ?? bedtime
            let sleepSec = durations[i].hours * 3600 + durations[i].minutes * 60
            let waketime = bedtime.addingTimeInterval(TimeInterval(sleepSec))

            let json: [String: Any] = [
                "id": 1000 + i,
                "side": (side ?? .left).rawValue,
                "enteredBedAt": Int(bedtime.timeIntervalSince1970),
                "leftBedAt": Int(waketime.timeIntervalSince1970),
                "sleepDurationSeconds": sleepSec,
                "timesExitedBed": i % 3 == 0 ? 1 : 0
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            let record = try JSONDecoder().decode(SleepRecord.self, from: data)
            records.append(record)
        }
        return records
    }

    // MARK: - Vitals

    func getVitals(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [VitalsRecord] {
        // Generate vitals for every night in the requested range (or last 7 nights)
        let cal = Calendar.current
        let now = Date()
        let rangeEnd = end ?? now
        let rangeStart = start ?? cal.date(byAdding: .day, value: -7, to: now)!
        var records: [VitalsRecord] = []
        var idCounter = 2000

        // Walk backwards from rangeEnd, generate one night per day
        var day = cal.startOfDay(for: rangeEnd)
        while day >= cal.startOfDay(for: rangeStart) {
            let nightStart = cal.date(bySettingHour: 23, minute: 0, second: 0,
                                       of: cal.date(byAdding: .day, value: -1, to: day) ?? day) ?? day
            let intervalMinutes = 5
            let totalPoints = 8 * 60 / intervalMinutes  // 8 hours
            // Slight per-night variation
            let nightSeed = Double(cal.component(.day, from: day))

            for i in 0..<totalPoints {
                let t = nightStart.addingTimeInterval(TimeInterval(i * intervalMinutes * 60))
                guard t >= rangeStart && t <= rangeEnd else { continue }
                let progress = Double(i) / Double(totalPoints)

                let hrBase: Double
                if progress < 0.15 {
                    hrBase = 65 - progress * 40
                } else if progress < 0.5 {
                    hrBase = 59 - (progress - 0.15) * 14
                } else if progress < 0.75 {
                    hrBase = 54 + (progress - 0.5) * 32
                } else {
                    hrBase = 62 + (progress - 0.75) * 20
                }
                let hrNoise = Double.random(in: -2...2) + sin(nightSeed) * 2

                let hrvBase: Double
                if progress < 0.5 {
                    hrvBase = 30 + (progress < 0.15 ? progress * 80 : 12 + (0.5 - progress) * 20)
                } else {
                    hrvBase = 25 + (0.75 - min(progress, 0.75)) * 40
                }
                let hrvNoise = Double.random(in: -5...5)

                let brBase = 13.5 + sin(progress * .pi * 4) * 1.5
                let brNoise = Double.random(in: -0.5...0.5)

                records.append(VitalsRecord(
                    id: idCounter,
                    side: (side ?? .left).rawValue,
                    heartRate: max(48, min(72, hrBase + hrNoise)),
                    hrv: max(15, min(55, hrvBase + hrvNoise)),
                    breathingRate: max(10, min(18, brBase + brNoise)),
                    date: t
                ))
                idCounter += 1
            }
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day.addingTimeInterval(-86400)
        }
        return records.sorted { $0.date < $1.date }
    }

    func getVitalsSummary(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> VitalsSummary {
        VitalsSummary(
            avgHeartRate: 58.3,
            minHeartRate: 52.0,
            maxHeartRate: 67.0,
            avgHRV: 34.2,
            avgBreathingRate: 13.8
        )
    }

    // MARK: - Movement

    func getMovement(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [MovementRecord] {
        let cal = Calendar.current
        let now = Date()
        let lastNightStart = cal.date(bySettingHour: 23, minute: 0, second: 0,
                                       of: cal.date(byAdding: .day, value: -1, to: now) ?? now) ?? now
        var records: [MovementRecord] = []
        let intervalMinutes = 5
        let totalPoints = 8 * 60 / intervalMinutes

        for i in 0..<totalPoints {
            let t = lastNightStart.addingTimeInterval(TimeInterval(i * intervalMinutes * 60))
            let progress = Double(i) / Double(totalPoints)

            // Low movement in deep sleep, higher during transitions and REM
            let baseMovement: Int
            if progress < 0.1 {
                baseMovement = Int.random(in: 15...40)    // falling asleep, some tossing
            } else if progress < 0.4 {
                baseMovement = Int.random(in: 2...12)     // deep sleep, very still
            } else if progress < 0.6 {
                baseMovement = Int.random(in: 8...30)     // REM/light transition
            } else if progress < 0.8 {
                baseMovement = Int.random(in: 3...15)     // second deep cycle
            } else {
                baseMovement = Int.random(in: 10...35)    // waking up
            }

            records.append(MovementRecord(
                id: 3000 + i,
                side: (side ?? .left).rawValue,
                totalMovement: baseMovement,
                date: t
            ))
        }
        return records
    }

    // MARK: - Actions (no-ops)

    func triggerAlarm(_ alarm: AlarmJob) async throws {
        await MainActor.run { Haptics.medium() }
    }

    func clearAlarm(side: Side) async throws {
        // no-op in demo
    }

    func reboot() async throws {
        // no-op in demo
    }

    func setInternetAccess(blocked: Bool) async throws {
        // no-op in demo
    }

    // MARK: - Calibration

    func getCalibrationStatus(side: Side) async throws -> CalibrationStatus {
        let sensor = { (type: String) -> CalibrationSensor in
            CalibrationSensor(
                id: type.hashValue,
                side: side.rawValue,
                sensorType: type,
                status: "completed",
                qualityScore: Double.random(in: 0.82...0.97),
                samplesUsed: Int.random(in: 180...240),
                errorMessage: nil
            )
        }
        return CalibrationStatus(
            capacitance: sensor("capacitance"),
            piezo: sensor("piezo"),
            temperature: sensor("temperature")
        )
    }

    func triggerCalibration(side: Side, sensorType: String) async throws -> CalibrationTriggerResponse {
        CalibrationTriggerResponse(triggered: true, message: "Demo calibration started")
    }

    func triggerFullCalibration() async throws -> CalibrationTriggerResponse {
        CalibrationTriggerResponse(triggered: true, message: "Demo full calibration started")
    }

    // MARK: - Disk / Files

    func getDiskUsage() async throws -> DiskUsage {
        DiskUsage(
            totalBytes: 4_294_967_296,   // 4 GB
            usedBytes: 2_147_483_648,    // 2 GB
            availableBytes: 2_147_483_648,
            usedPercent: 50.0
        )
    }

    func getFileCount() async throws -> FileCount {
        FileCount(
            rawFiles: FileCount.RawFileCount(left: 342, right: 338),
            totalSizeMB: 186.4
        )
    }

    // MARK: - Beta Features

    func getVersion() async throws -> SystemVersion {
        SystemVersion(
            branch: "demo",
            commitHash: "abc1234def5678",
            commitTitle: "Demo mode",
            buildDate: ISO8601DateFormatter().string(from: Date())
        )
    }

    func snoozeAlarm(side: Side, duration: Int) async throws -> SnoozeResponse {
        SnoozeResponse(
            success: true,
            snoozeUntil: Int(Date().addingTimeInterval(TimeInterval(duration)).timeIntervalSince1970)
        )
    }

    func getWaterLevelLatest() async throws -> WaterLevelReading? {
        WaterLevelReading(
            id: 1,
            level: "ok",
            rawValue: "512",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    func getWaterLevelTrend(hours: Int) async throws -> WaterLevelTrend {
        WaterLevelTrend(
            totalReadings: 48,
            okPercent: 96,
            lowPercent: 4,
            trend: "stable",
            latestLevel: "ok"
        )
    }

    func getAmbientLightLatest() async throws -> AmbientLightReading? {
        // Return a reading appropriate for the time of day
        let hour = Calendar.current.component(.hour, from: Date())
        let lux: Double = (hour >= 22 || hour < 6) ? 2.3 : (hour < 8 ? 15.0 : 180.0)
        return AmbientLightReading(
            id: 1,
            lux: lux,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    func getBedTempHistory(start: Date, end: Date, limit: Int, unit: String) async throws -> [BedTempReading] { [] }
    func startRunOnce(side: Side, setPoints: [[String: Any]], wakeTime: String) async throws -> RunOnceStartResponse { RunOnceStartResponse(sessionId: 1, expiresAt: Int(Date().timeIntervalSince1970) + 28800) }
    func getActiveRunOnce(side: Side) async throws -> RunOnceSession? { nil }
    func cancelRunOnce(side: Side) async throws {}

    func updateSleepRecord(id: Int, enteredBedAt: Date?, leftBedAt: Date?) async throws {
        // no-op in demo
    }

    func deleteSleepRecord(id: Int) async throws {
        // no-op in demo
    }

    func dismissPrimeNotification() async throws {
        // no-op in demo
    }
}
