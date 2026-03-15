import Foundation
import Observation

@MainActor
@Observable
final class StatusManager {
    var serverStatus: ServerStatus?
    var services: Services?
    var isLoading = false
    var error: String?
    var lastUpdated: Date?

    private let api: FreeSleepAPIProtocol
    private var pollingTask: Task<Void, Never>?

    init(api: FreeSleepAPIProtocol) {
        self.api = api
    }

    // MARK: - Computed

    func categories(schedules: Schedules? = nil) -> [ServiceCategory] {
        guard let status = serverStatus else { return [] }

        // Compute next alarm subtitle from schedule data
        let alarmSubtitle = Self.nextAlarmSubtitle(from: schedules)

        // Compute system date subtitle
        let systemSubtitle = Self.systemDateSubtitle(from: status.systemDate)

        return [
            ServiceCategory(
                name: "Core Services",
                description: "Essential server components",
                iconName: "server.rack",
                iconColorHex: "4a90d9",
                services: [status.express, status.database, status.logger, status.jobs]
            ),
            ServiceCategory(
                name: "Hardware",
                description: "Pod hardware interfaces",
                iconName: "cpu",
                iconColorHex: "a080d0",
                services: [status.podSocket, status.podSocketMonitor]
            ),
            ServiceCategory(
                name: "Schedules",
                description: "Automated schedule managers",
                subtitle: alarmSubtitle,
                iconName: "calendar",
                iconColorHex: "d4a84a",
                services: [status.temperatureSchedule, status.alarmSchedule, status.powerSchedule,
                           status.primeSchedule, status.rebootSchedule]
            ),
            ServiceCategory(
                name: "Biometrics",
                description: "Sleep tracking and analysis",
                iconName: "heart.fill",
                iconColorHex: "e05050",
                services: [status.analyzeSleepLeft, status.analyzeSleepRight,
                           status.biometricsStream, status.biometricsInstallation].compactMap { $0 }
            ),
            ServiceCategory(
                name: "Calibration",
                description: "Sensor calibration jobs",
                iconName: "tuningfork",
                iconColorHex: "4ecdc4",
                services: [status.biometricsCalibrationLeft, status.biometricsCalibrationRight].compactMap { $0 }
            ),
            ServiceCategory(
                name: "System",
                description: "Time sync and utilities",
                subtitle: systemSubtitle,
                iconName: "gear",
                iconColorHex: "888888",
                services: [status.systemDate]
            )
        ].filter { !$0.services.isEmpty }
    }

    // MARK: - Subtitle Helpers

    private static func nextAlarmSubtitle(from schedules: Schedules?) -> String? {
        guard let schedules else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)

        // Map Calendar weekday (1=Sun) to DayOfWeek
        let dayOrder: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let todayIndex = currentWeekday - 1

        // Check today and next 7 days for the next enabled alarm
        for dayOffset in 0..<7 {
            let dayIndex = (todayIndex + dayOffset) % 7
            let day = dayOrder[dayIndex]

            // Check left side alarm
            let leftAlarm = schedules.left[day].alarm
            let rightAlarm = schedules.right[day].alarm

            let alarms = [(leftAlarm, "L"), (rightAlarm, "R")].filter { $0.0.enabled }
            guard let earliest = alarms.min(by: { $0.0.time < $1.0.time }) else { continue }

            // If today, check if the alarm time has passed
            if dayOffset == 0 {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                if let alarmDate = formatter.date(from: earliest.0.time) {
                    let alarmComponents = calendar.dateComponents([.hour, .minute], from: alarmDate)
                    let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
                    if let alarmHour = alarmComponents.hour, let alarmMin = alarmComponents.minute,
                       let nowHour = nowComponents.hour, let nowMin = nowComponents.minute {
                        if alarmHour * 60 + alarmMin <= nowHour * 60 + nowMin {
                            continue // Already passed today
                        }
                    }
                }
            }

            let dayLabel = dayOffset == 0 ? "Today" : dayOffset == 1 ? "Tomorrow" : day.displayName
            return "Next alarm: \(dayLabel) at \(earliest.0.time)"
        }

        return "No alarms scheduled"
    }

    private static func systemDateSubtitle(from info: StatusInfo) -> String? {
        // If the message contains a date, try to parse and show drift
        // Otherwise just show the message if it's useful
        guard !info.message.isEmpty, info.message != "OK" else { return nil }
        return info.message
    }

    var healthyCount: Int {
        serverStatus?.healthyCount ?? 0
    }

    var totalCount: Int {
        serverStatus?.totalCount ?? 0
    }

    var healthProgress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(healthyCount) / Double(totalCount)
    }

    // MARK: - Fetch

    func fetchAll() async {
        isLoading = true
        error = nil

        async let statusTask: () = fetchServerStatus()
        async let servicesTask: () = fetchServices()
        _ = await (statusTask, servicesTask)

        lastUpdated = Date()
        isLoading = false
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchAll()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Services Control

    func toggleBiometrics() async {
        guard var services else { return }
        services.biometrics.enabled.toggle()
        self.services = services
        do {
            self.services = try await api.updateServices(services)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleSentryLogging() async {
        guard var services else { return }
        services.sentryLogging.enabled.toggle()
        self.services = services
        do {
            self.services = try await api.updateServices(services)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Retry

    func retryService(_ service: StatusInfo) async {
        // Re-fetch to pick up any status changes after manual intervention
        await fetchAll()
    }

    // MARK: - Private

    private func fetchServerStatus() async {
        do {
            serverStatus = try await api.getServerStatus()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchServices() async {
        do {
            services = try await api.getServices()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
