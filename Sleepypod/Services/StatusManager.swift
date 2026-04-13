import Foundation
import Observation

@MainActor
@Observable
final class StatusManager {
    var serverStatus: ServerStatus?
    var services: Services?
    var logSources: [LogSource] = []
    var isLoading = false
    var error: String?
    var lastUpdated: Date?
    var isInternetBlocked = false
    private var internetCooldownUntil: Date?

    private let api: SleepypodProtocol
    private var pollingTask: Task<Void, Never>?

    init(api: SleepypodProtocol) {
        self.api = api
    }

    // MARK: - Computed

    func categories(schedules: Schedules? = nil) -> [ServiceCategory] {
        guard let status = serverStatus else { return [] }

        // Compute next alarm subtitle from schedule data
        let alarmSubtitle = Self.nextAlarmSubtitle(from: schedules)

        return [
            ServiceCategory(
                name: "Core",
                description: "Server, database, wifi, and scheduler",
                iconName: "server.rack",
                iconColorHex: "4a90d9",
                services: [status.express, status.database, status.logger, status.jobs]
            ),
            ServiceCategory(
                name: "Hardware",
                description: "DAC socket and monitoring",
                iconName: "cpu",
                iconColorHex: "a080d0",
                services: [status.podSocket, status.podSocketMonitor]
            ),
            ServiceCategory(
                name: "Schedules",
                description: "Temperature, power, and alarm jobs",
                subtitle: alarmSubtitle,
                iconName: "calendar",
                iconColorHex: "d4a84a",
                services: [status.temperatureSchedule, status.alarmSchedule, status.powerSchedule,
                           status.primeSchedule, status.rebootSchedule]
            )
            // Biometrics and Calibration are shown as individual cards
            // with real data from their own endpoints — not from ServerStatus
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
        async let internetTask: () = fetchInternetStatus()
        async let logSourcesTask: () = fetchLogSources()
        _ = await (statusTask, servicesTask, internetTask, logSourcesTask)

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

    // MARK: - Internet Access

    func setInternetAccess(blocked: Bool) async {
        isInternetBlocked = blocked
        internetCooldownUntil = Date().addingTimeInterval(10) // Don't let polls override for 10s
        do {
            try await api.setInternetAccess(blocked: blocked)
        } catch {
            isInternetBlocked = !blocked
            internetCooldownUntil = nil
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

    private func fetchInternetStatus() async {
        // Don't override optimistic update during cooldown
        if let cooldown = internetCooldownUntil, Date() < cooldown { return }
        internetCooldownUntil = nil
        do {
            struct InternetStatus: Decodable { var blocked: Bool }
            let result: InternetStatus = try await {
                let base = UserDefaults.standard.string(forKey: "podIPAddress") ?? ""
                guard !base.isEmpty,
                      let url = URL(string: "http://\(base):3000/api/trpc/system.internetStatus?input=%7B%22json%22%3A%7B%7D%7D") else { return InternetStatus(blocked: false) }
                let (data, _) = try await URLSession.shared.data(from: url)
                struct E<T: Decodable>: Decodable { let result: R<T> }
                struct R<T: Decodable>: Decodable { let data: D<T> }
                struct D<T: Decodable>: Decodable { let json: T }
                return try JSONDecoder().decode(E<InternetStatus>.self, from: data).result.data.json
            }()
            isInternetBlocked = result.blocked
        } catch {
            // Keep previous value
        }
    }

    private func fetchServices() async {
        do {
            services = try await api.getServices()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchLogSources() async {
        do {
            logSources = try await api.getLogSources()
        } catch {
            // Non-critical — keep previous value
        }
    }
}
