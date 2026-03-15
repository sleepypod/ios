import SwiftUI

@main
struct SleepypodApp: App {
    @State private var deviceManager: DeviceManager
    @State private var scheduleManager: ScheduleManager
    @State private var metricsManager: MetricsManager
    @State private var statusManager: StatusManager
    @State private var settingsManager: SettingsManager

    init() {
        let client = APIBackend.current.createClient()
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
    @State private var selectedTab = "temp"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Temp", systemImage: "thermometer.medium", value: "temp") {
                TempScreen()
            }
            Tab("Schedule", systemImage: "calendar", value: "schedule") {
                ScheduleScreen()
            }
            Tab("Data", systemImage: "chart.bar.fill", value: "data") {
                DataScreen()
            }
            Tab("Status", systemImage: "heart.text.clipboard", value: "status") {
                StatusScreen()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: "settings") {
                SettingsScreen()
            }
        }
        .onChange(of: selectedTab) {
            Haptics.tap()
        }
    }
}
