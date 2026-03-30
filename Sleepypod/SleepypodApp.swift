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
            .onReceive(NotificationCenter.default.publisher(for: .switchToTempTab)) { notification in
                if let side = notification.object as? SideSelection {
                    deviceManager.selectedSide = side
                }
                selectedTab = "temp"
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
            // Sensor demo stream starts automatically when Sensors tab is visited
            // via BedSensorScreen.onAppear -> connect() -> startDemoStream()
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

    @State private var ringScale: CGFloat = 0.8
    @State private var phase: CGFloat = 0

    private var isActive: Bool {
        podDiscovery.isSearching || deviceManager.isConnecting ||
        podDiscovery.status == .scanning ||
        { if case .resolving = podDiscovery.status { return true }; return false }() ||
        { if case .connected = podDiscovery.status { return true }; return false }()
    }

    private var statusText: String {
        switch podDiscovery.status {
        case .idle:
            return "Connecting..."
        case .scanning:
            return "Scanning network..."
        case .found:
            return "sleepypod"
        case .resolving(let name):
            if let ip = resolvedIP {
                return "Found sleepypod @ \(ip)"
            }
            return "Found sleepypod @ \(name)"
        case .connected(let ip):
            return "Connecting to \(ip)..."
        case .failed:
            return "Could not find pod"
        }
    }

    private var statusColor: Color {
        switch podDiscovery.status {
        case .idle: return Theme.textMuted
        case .scanning, .found, .resolving, .connected: return Theme.textSecondary
        case .failed: return Theme.error
        }
    }

    private var resolvedIP: String? {
        if case .connected(let ip) = podDiscovery.status { return ip }
        if deviceManager.isConnecting { return settingsManager.podIP.isEmpty ? nil : settingsManager.podIP }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Pulsing logo with radial gradient
            ZStack {
                // Pulsing radial gradient — starts black to match icon bg, fades to accent
                RadialGradient(
                    colors: [
                        Color.black,
                        Theme.accent.opacity(0.12),
                        Theme.accent.opacity(0.04),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 35,
                    endRadius: 130
                )
                .frame(width: 260, height: 260)
                .scaleEffect(ringScale)
                .blur(radius: 6)

                // Outer glow rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.accent.opacity(0.08 - Double(i) * 0.02), lineWidth: 2)
                        .frame(width: 80 + CGFloat(i) * 30, height: 80 + CGFloat(i) * 30)
                        .scaleEffect(ringScale + CGFloat(i) * 0.05)
                }

                // Center logo
                Image("WelcomeLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .scaleEffect(ringScale)

                // Arc spinner — always visible (auto-connecting)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(phase))
            }

            // Status text
            Text(statusText)
                .font(.subheadline)
                .foregroundColor(statusColor)
                .padding(.top, 20)
                .animation(.easeInOut(duration: 0.3), value: statusText)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                // Retry — only after failure
                if podDiscovery.status == .failed {
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
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                // Manual IP — accordion (muted until expanded)
                DisclosureGroup {
                    HStack(spacing: 8) {
                        TextField("192.168.1.88", text: Binding(
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
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 6) {
                        Text("Enter IP manually")
                            .font(.caption)
                    }
                    .foregroundColor(Theme.textMuted)
                }
                .tint(Theme.textMuted)
                .accentColor(Theme.textMuted)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                ringScale = 1.0
            }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
    }
}
