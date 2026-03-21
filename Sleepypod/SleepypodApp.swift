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
    @State private var sensorStream = SensorStreamService()
    @State private var notificationRelay = NotificationRelay()

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
                .environment(sensorStream)
                .environment(notificationRelay)
                .preferredColorScheme(.dark)
                .task {
                    await notificationRelay.requestPermission()
                    sensorStream.notificationRelay = notificationRelay
                }
        }
    }
}

struct ContentView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PodDiscovery.self) private var podDiscovery
    @Environment(SensorStreamService.self) private var sensorStream
    @State private var selectedTab = "temp"
    @State private var showWelcome = false

    private var isConnected: Bool {
        deviceManager.isConnected
    }

    private var isDemo: Bool {
        APIBackend.current.isDemo
    }

    var body: some View {
        ZStack {
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
                Tab("Sensors", systemImage: "waveform", value: "sensors") {
                    if isConnected {
                        BedSensorScreen()
                    } else {
                        DisconnectedTabView(tab: "Sensors", selectedTab: $selectedTab)
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

            // Demo mode banner — floating at top
            if isDemo && isConnected {
                VStack {
                    DemoModeBanner()
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeScreen(onConnect: {
                // Dismiss welcome, show the main app with DisconnectedTabView
                // which has step indicators, manual IP entry, and retry
                showWelcome = false
                deviceManager.startPolling()
                Task { await startConnection() }
            }, onDemo: {
                showWelcome = false
                enterDemoMode()
            })
        }
        .task {
            // Show welcome if no pod IP and not in demo mode
            if settingsManager.podIP.isEmpty && !isDemo {
                showWelcome = true
                return
            }

            deviceManager.startPolling()

            // Demo mode — just fetch mock status, skip mDNS
            if isDemo {
                await deviceManager.fetchStatus()
                return
            }

            await startConnection()
        }
        .onChange(of: deviceManager.isConnected) {
            if deviceManager.isConnected {
                podDiscovery.status = .idle
                // Auto-dismiss welcome screen when connection succeeds
                if showWelcome { showWelcome = false }
            }
        }
        .onChange(of: sensorStream.latestDeviceStatus?.ts) { _, _ in
            if let status = sensorStream.latestDeviceStatus {
                deviceManager.applyWebSocketStatus(status)
                deviceManager.isReceivingWebSocket = true
            }
        }
        .onChange(of: sensorStream.isConnected) { _, connected in
            if !connected {
                deviceManager.isReceivingWebSocket = false
            }
        }
    }

    // MARK: - Connection Flow

    private func startConnection() async {
        if !settingsManager.podIP.isEmpty {
            Haptics.light()
            podDiscovery.status = .found("Saved: \(settingsManager.podIP)")
            podDiscovery.connectedPodName = settingsManager.podIP

            Haptics.light()
            podDiscovery.status = .resolving(settingsManager.podIP)
            await deviceManager.fetchStatus()

            if deviceManager.isConnected {
                Haptics.medium()
                podDiscovery.status = .connected(settingsManager.podIP)
                return
            }
            Haptics.heavy()
            podDiscovery.status = .failed
        }

        // Saved IP failed or empty — try mDNS
        if let ip = await podDiscovery.autoConnect(settingsManager: settingsManager, deviceManager: deviceManager) {
            // autoConnect found and saved an IP — fetch status to confirm connection
            Log.discovery.info("autoConnect resolved to \(ip), fetching status...")
            await deviceManager.fetchStatus()
        }
    }

    private func enterDemoMode() {
        APIBackend.current = .demo
        let client = APIBackend.demo.createClient()
        deviceManager.switchBackend(client)
    }
}

// MARK: - Welcome Screen

struct WelcomeScreen: View {
    let onConnect: () -> Void
    let onDemo: () -> Void

    @State private var pulse = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // Subtle radial glow
            RadialGradient(
                colors: [Theme.accent.opacity(pulse ? 0.08 : 0.04), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 300
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }

            VStack(spacing: 0) {
                Spacer()

                // App logo
                Image("WelcomeLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.bottom, 16)

                Text("sleepypod")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 8)

                Text("Connect to your pod via Bonjour\nor enter its IP address.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        Haptics.medium()
                        onConnect()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Connect")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.light()
                        onDemo()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle")
                            Text("Explore Demo")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)

                Spacer()
                Spacer()
            }
        }
    }
}

// MARK: - Demo Mode Banner

struct DemoModeBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.circle.fill")
                .font(.caption2)
            Text("Demo Mode")
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(Theme.amber)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.amber.opacity(0.15))
        .clipShape(Capsule())
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
                    icon: "WelcomeLogo",
                    title: deviceName ?? "Finding sleepypod",
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
                            Text("Search for sleepypod")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    // Manual IP entry
                    HStack(spacing: 8) {
                        TextField("Pod IP address", text: Binding(
                            get: { settingsManager.podIP },
                            set: { settingsManager.podIP = $0 }
                        ))
                        .font(.system(size: 14, design: .monospaced))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.cardBorder, lineWidth: 1)
                        )

                        Button {
                            Haptics.medium()
                            deviceManager.retryConnection()
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                                .foregroundColor(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(settingsManager.podIP.isEmpty)
                    }
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
        if deviceManager.isConnecting { return .active }
        if deviceManager.isConnected { return .done }
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
                } else if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(stepColor(state))
                } else if state == .failed {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(stepColor(state))
                } else if icon == "WelcomeLogo" {
                    Image("WelcomeLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: icon)
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
