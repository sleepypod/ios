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

    // MARK: - Side Names (single source of truth)

    /// Display name for the left side. Falls back to "Left" if not set or empty.
    var leftName: String {
        let name = settings?.left.name ?? ""
        return name.isEmpty ? "Left" : name
    }

    /// Display name for the right side. Falls back to "Right" if not set or empty.
    var rightName: String {
        let name = settings?.right.name ?? ""
        return name.isEmpty ? "Right" : name
    }

    /// Display name for a given side.
    func sideName(for side: Side) -> String {
        side == .left ? leftName : rightName
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
        set {
            // Strip IPv6 zone IDs (%en0, %%en0) and whitespace
            var clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pct = clean.firstIndex(of: "%") {
                clean = String(clean[clean.startIndex..<pct])
            }
            // Strip ::ffff: IPv4-mapped prefix
            if clean.hasPrefix("::ffff:") {
                clean = String(clean.dropFirst(7))
            }
            UserDefaults.standard.set(clean, forKey: "podIPAddress")
        }
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

    func updateRebootTime(_ time: String) async {
        guard var settings else { return }
        settings.rebootTime = time
        self.settings = settings
        await saveSettings(settings)
    }

    func togglePrimePodDaily() async {
        guard var settings else { return }
        settings.primePodDaily.enabled.toggle()
        self.settings = settings
        await saveSettings(settings)
    }

    func updateLEDBrightness(_ brightness: Int) async {
        // LED brightness is in DeviceStatus.settings, not PodSettings
        // Needs device.setLedBrightness endpoint (core#159)
    }

    func updateSideName(_ side: Side, name: String) async {
        guard var settings else { return }
        switch side {
        case .left: settings.left.name = name
        case .right: settings.right.name = name
        }
        self.settings = settings
        await saveSettings(settings)
    }

    func toggleAwayMode(_ side: Side) async {
        guard var settings else { return }
        switch side {
        case .left: settings.left.awayMode.toggle()
        case .right: settings.right.awayMode.toggle()
        }
        self.settings = settings
        await saveSettings(settings)
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
