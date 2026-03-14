import SwiftUI

@main
struct SleepypodApp: App {
    @State private var deviceManager: DeviceManager
    @State private var scheduleManager: ScheduleManager
    @State private var metricsManager: MetricsManager
    @State private var statusManager: StatusManager
    @State private var settingsManager: SettingsManager

    init() {
        let client = FreeSleepClient()
        let device = DeviceManager(api: client)
        let schedule = ScheduleManager(api: client)
        let metrics = MetricsManager(api: client)
        let status = StatusManager(api: client)
        let settings = SettingsManager(api: client)

        _deviceManager = State(initialValue: device)
        _scheduleManager = State(initialValue: schedule)
        _metricsManager = State(initialValue: metrics)
        _statusManager = State(initialValue: status)
        _settingsManager = State(initialValue: settings)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deviceManager)
                .environment(scheduleManager)
                .environment(metricsManager)
                .environment(statusManager)
                .environment(settingsManager)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Temp", systemImage: "thermometer.medium") {
                TempScreen()
            }
            Tab("Schedule", systemImage: "calendar") {
                ScheduleScreen()
            }
            Tab("Data", systemImage: "chart.bar.fill") {
                DataScreen()
            }
            Tab("Status", systemImage: "heart.text.clipboard") {
                StatusScreen()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsScreen()
            }
        }
    }
}
