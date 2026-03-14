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

    var categories: [ServiceCategory] {
        guard let status = serverStatus else { return [] }
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
                services: [status.franken, status.frankenMonitor]
            ),
            ServiceCategory(
                name: "Schedules",
                description: "Automated schedule managers",
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
                description: "System utilities",
                iconName: "gear",
                iconColorHex: "888888",
                services: [status.systemDate]
            )
        ].filter { !$0.services.isEmpty }
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
                try? await Task.sleep(for: .seconds(30))
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
