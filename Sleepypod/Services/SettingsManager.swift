import Foundation
import Observation

@MainActor
@Observable
final class SettingsManager {
    var settings: PodSettings?
    var isLoading = false
    var error: String?

    private let api: SleepypodProtocol

    init(api: SleepypodProtocol) {
        self.api = api
    }

    // MARK: - Computed

    var temperatureFormat: TemperatureFormat {
        // Relative is local-only (API only knows F/C)
        if let local = UserDefaults.standard.string(forKey: "temperatureFormat"),
           let format = TemperatureFormat(rawValue: local) {
            return format
        }
        return settings?.temperatureFormat ?? .fahrenheit
    }

    var timeZone: String {
        settings?.timeZone ?? TimeZone.current.identifier
    }

    var podIP: String {
        get { UserDefaults.standard.string(forKey: "podIPAddress") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "podIPAddress") }
    }

    // MARK: - Fetch

    func fetchSettings() async {
        isLoading = true
        error = nil
        do {
            settings = try await api.getSettings()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Updates

    func updateTimeZone(_ tz: String) async {
        guard var settings else { return }
        settings.timeZone = tz
        self.settings = settings
        await saveSettings(settings)
    }

    func updateTemperatureFormat(_ format: TemperatureFormat) async {
        // Always store locally (for relative mode)
        UserDefaults.standard.set(format.rawValue, forKey: "temperatureFormat")

        // Only sync F/C to the server — relative is local-only
        if format != .relative {
            guard var settings else { return }
            settings.temperatureFormat = format
            self.settings = settings
            await saveSettings(settings)
        }
    }

    func toggleRebootDaily() async {
        guard var settings else { return }
        settings.rebootDaily.toggle()
        self.settings = settings
        await saveSettings(settings)
    }

    func updateLEDBrightness(_ brightness: Int) async {
        // LED brightness is in DeviceStatus.settings, not PodSettings
        // This would need to go through DeviceManager
        // For now, this is a placeholder
    }

    func reboot() async {
        do {
            try await api.reboot()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Private

    private func saveSettings(_ settings: PodSettings) async {
        do {
            self.settings = try await api.updateSettings(settings)
        } catch {
            self.error = error.localizedDescription
            await fetchSettings()
        }
    }
}
