import SwiftUI

@main
struct SleepypodApp: App {
    @State private var deviceManager: DeviceManager
    @State private var scheduleManager: ScheduleManager
    @State private var metricsManager: MetricsManager
    @State private var statusManager: StatusManager
    @State private var settingsManager: SettingsManager
    @State private var updateChecker = UpdateChecker()
    @State private var podDiscovery = PodDiscovery()
    @State private var userProfile = UserProfile()

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
                .environment(podDiscovery)
                .environment(userProfile)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PodDiscovery.self) private var podDiscovery
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
                    DisconnectedTabView(tab: "Schedule", selectedTab: $selectedTab)
                }
            }
            Tab("Biometrics", systemImage: "heart.text.clipboard", value: "health") {
                if isConnected {
                    HealthScreen()
                } else {
                    DisconnectedTabView(tab: "Health", selectedTab: $selectedTab)
                }
            }
            Tab("Status", systemImage: "antenna.radiowaves.left.and.right", value: "status") {
                if isConnected {
                    StatusScreen()
                } else {
                    DisconnectedTabView(tab: "Status", selectedTab: $selectedTab)
                }
            }
        }
        .onChange(of: selectedTab) {
            Haptics.tap()
        }
        .task {
            deviceManager.startPolling()

            if !settingsManager.podIP.isEmpty {
                // Show saved-IP connection in the timeline
                podDiscovery.status = .found("Saved: \(settingsManager.podIP)")
                podDiscovery.connectedPodName = settingsManager.podIP

                podDiscovery.status = .resolving(settingsManager.podIP)
                await deviceManager.fetchStatus()

                if deviceManager.isConnected {
                    podDiscovery.status = .connected(settingsManager.podIP)
                    return
                }
                podDiscovery.status = .failed
            }

            // Saved IP failed or empty — try mDNS
            await podDiscovery.autoConnect(settingsManager: settingsManager, deviceManager: deviceManager)
        }
        .onChange(of: deviceManager.isConnected) {
            if deviceManager.isConnected {
                podDiscovery.status = .idle
            }
        }
    }
}

struct DisconnectedTabView: View {
    let tab: String
    var selectedTab: Binding<String>?
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PodDiscovery.self) private var podDiscovery

    private var isActive: Bool {
        podDiscovery.isSearching || deviceManager.isConnecting ||
        podDiscovery.status == .scanning ||
        { if case .resolving = podDiscovery.status { return true }; return false }() ||
        { if case .connected = podDiscovery.status { return true }; return false }()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Step indicators
            VStack(spacing: 0) {
                connectionStep(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Scanning network",
                    state: scanState
                )

                stepConnector(active: scanState == .done)

                connectionStep(
                    icon: "bed.double.fill",
                    title: deviceName ?? "Finding Sleepypod",
                    state: findState
                )

                stepConnector(active: findState == .done)

                connectionStep(
                    icon: "link",
                    title: resolvedIP ?? "Resolving address",
                    state: resolveState
                )

                stepConnector(active: resolveState == .done)

                connectionStep(
                    icon: "wifi",
                    title: "Connecting",
                    state: connectState
                )
            }
            .padding(.horizontal, 48)

            // Actions — centered between steps and tab bar
            if !isActive {
                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Haptics.light()
                        Task {
                            await podDiscovery.autoConnect(
                                settingsManager: settingsManager,
                                deviceManager: deviceManager
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Search for Sleepypod")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.light()
                        selectedTab?.wrappedValue = "settings"
                    } label: {
                        Text("Enter IP manually")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Step States

    private enum StepState {
        case idle, active, done, failed
    }

    private var deviceName: String? {
        if case .found(let n) = podDiscovery.status { return n }
        if case .resolving(let n) = podDiscovery.status { return n }
        if let n = podDiscovery.connectedPodName { return n }
        return nil
    }

    private var resolvedIP: String? {
        if case .connected(let ip) = podDiscovery.status { return ip }
        if deviceManager.isConnecting { return settingsManager.podIP.isEmpty ? nil : settingsManager.podIP }
        return nil
    }

    private var scanState: StepState {
        switch podDiscovery.status {
        case .scanning: return .active
        case .found, .resolving, .connected: return .done
        case .failed: return .failed
        case .idle: return .idle
        }
    }

    private var findState: StepState {
        switch podDiscovery.status {
        case .scanning: return .idle
        case .found: return .active
        case .resolving, .connected: return .done
        case .failed: return .failed
        case .idle: return .idle
        }
    }

    private var resolveState: StepState {
        switch podDiscovery.status {
        case .scanning, .found: return .idle
        case .resolving: return .active
        case .connected: return .done
        case .failed: return .failed
        case .idle: return .idle
        }
    }

    private var connectState: StepState {
        switch podDiscovery.status {
        case .scanning, .found, .resolving: return .idle
        case .connected: return .active
        case .failed: return .failed
        case .idle: return .idle
        }
    }

    // MARK: - Step Views

    private func connectionStep(icon: String, title: String, state: StepState) -> some View {
        HStack(spacing: 14) {
            ZStack {
                // Glow for active state
                if state == .active {
                    Circle()
                        .fill(Theme.accent.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .blur(radius: 4)
                }

                Circle()
                    .fill(stepColor(state).opacity(0.15))
                    .frame(width: 36, height: 36)

                if state == .active {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: state == .done ? "checkmark" : state == .failed ? "xmark" : icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(stepColor(state))
                }
            }
            .frame(width: 44, height: 44)

            Text(title)
                .font(.subheadline)
                .foregroundColor(state == .idle ? Theme.textMuted : .white)
                .animation(.easeInOut(duration: 0.3), value: title)

            Spacer()
        }
    }

    private func stepConnector(active: Bool) -> some View {
        HStack {
            Rectangle()
                .fill(active ? Theme.accent.opacity(0.4) : Color(hex: "333333"))
                .frame(width: 2, height: 20)
                .padding(.leading, 21)
                .animation(.easeInOut(duration: 0.3), value: active)
            Spacer()
        }
    }

    private func stepColor(_ state: StepState) -> Color {
        switch state {
        case .idle: Theme.textMuted
        case .active: Theme.accent
        case .done: Theme.healthy
        case .failed: Theme.error
        }
    }
}
