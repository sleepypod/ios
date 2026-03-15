import SwiftUI

@main
struct SleepypodApp: App {
    @State private var deviceManager: DeviceManager
    @State private var scheduleManager: ScheduleManager
    @State private var metricsManager: MetricsManager
    @State private var statusManager: StatusManager
    @State private var settingsManager: SettingsManager
    @State private var updateChecker = UpdateChecker()

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
                .environment(updateChecker)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @State private var selectedTab = "temp"

    private var isConnected: Bool {
        deviceManager.isConnected
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Temp", systemImage: "thermometer.medium", value: "temp") {
                TempScreen()
            }
            Tab("Schedule", systemImage: "calendar", value: "schedule") {
                if isConnected {
                    ScheduleScreen()
                } else {
                    DisconnectedTabView(tab: "Schedule")
                }
            }
            Tab("Data", systemImage: "chart.bar.fill", value: "data") {
                if isConnected {
                    DataScreen()
                } else {
                    DisconnectedTabView(tab: "Data")
                }
            }
            Tab("Status", systemImage: "heart.text.clipboard", value: "status") {
                if isConnected {
                    StatusScreen()
                } else {
                    DisconnectedTabView(tab: "Status")
                }
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

struct DisconnectedTabView: View {
    let tab: String
    @Environment(DeviceManager.self) private var deviceManager

    private var podIP: String {
        UserDefaults.standard.string(forKey: "podIPAddress") ?? ""
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if deviceManager.isConnecting {
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(1.2)
                    .padding(.bottom, 8)
                Text("Connecting to pod…")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            } else {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 36))
                    .foregroundColor(Theme.error)
                    .padding(.bottom, 4)

                if podIP.isEmpty {
                    Text("No pod configured")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Text("Set your pod IP address in Settings")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                } else {
                    Text("Could not connect to \(podIP)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Text("Check that your pod is powered on and reachable")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }

                Button {
                    Haptics.light()
                    deviceManager.retryConnection()
                } label: {
                    Text("Retry")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
