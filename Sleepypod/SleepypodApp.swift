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
    @State private var healthSync = HealthSyncService()

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
                .environment(healthSync)
                .preferredColorScheme(userProfile.appearance.colorScheme)
                .foregroundStyle(Theme.text1)
                .tint(Theme.text1)
                .task {
                    if !DebugRoute.marketingCapture { await notificationRelay.requestPermission() }
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
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(MetricsManager.self) private var metricsManager
    @Environment(StatusManager.self) private var statusManager
    @Environment(HealthSyncService.self) private var healthSync
    @Environment(UserProfile.self) private var profile
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = Self.initialTab
    @State private var showWelcome = false

    private static var initialTab: String {
        switch DebugRoute.current {
        case "schedule": "schedule"
        case "sleep", "week", "weektrend", "month", "watch": "sleep"
        default: "temp"
        }
    }

    /// Outline glyphs in both states, as drawn in the source tab bar.
    private func tabLabel(_ title: String, _ symbol: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol).environment(\.symbolVariants, .none) }
    }

    private var isConnected: Bool {
        deviceManager.isConnected
    }

    private var isDemo: Bool {
        APIBackend.current.isDemo
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab(value: "temp") {
                    TempScreen()
                } label: { tabLabel("Temp", "thermometer.medium") }
                Tab(value: "schedule") {
                    if isConnected {
                        ScheduleScreen()
                    } else {
                        NavigationStack { DisconnectedTabView(tab: "Schedule", selectedTab: $selectedTab).settingsToolbar() }
                    }
                } label: { tabLabel("Schedule", "calendar") }
                Tab(value: "sleep") {
                    if isConnected { SleepScreen() }
                    else { NavigationStack { DisconnectedTabView(tab: "Sleep", selectedTab: $selectedTab).settingsToolbar() } }
                } label: { tabLabel("Sleep", "moon") }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .onChange(of: selectedTab) {
                Haptics.tap()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToTempTab)) { notification in
                if let side = notification.object as? SideSelection {
                    deviceManager.selectedSide = side
                }
                selectedTab = "temp"
            }

        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeScreen(onConnect: {
                profile.onboardingComplete = true
                showWelcome = false
                deviceManager.startPolling()
            }, onDemo: {
                enterDemoMode()
            })
        }
        .task {
            deviceManager.selectSide(profile.defaultSide == .left ? .left : .right)
            scheduleManager.selectedSide = profile.defaultSide == .left ? .left : .right
            metricsManager.selectedSide = profile.defaultSide
            // Run setup until all three onboarding steps are complete.
            if !profile.onboardingComplete && !isDemo {
                showWelcome = true
                return
            }

            // Demo mode — just fetch mock status, skip mDNS
            // Sensor demo stream starts automatically when Sensors tab is visited
            // via BedSensorScreen.onAppear -> connect() -> startDemoStream()
            if isDemo {
                await deviceManager.fetchStatus()
                deviceManager.startPolling()
                return
            }

            // Fetch once via startConnection, then hand off to polling. startPolling
            // detects the populated deviceStatus and skips its redundant first tick.
            await startConnection()
            deviceManager.startPolling()
        }
        .task(id: "\(scenePhase)-\(profile.defaultSide.rawValue)-\(healthSync.enabled)-\(healthSync.preferences.signature)-\(isConnected)-\(settingsManager.podIP)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                if deviceManager.isConnected {
                    await healthSync.syncRecent(api: APIBackend.current.createClient(), podID: settingsManager.podID,
                                                side: profile.defaultSide, demo: isDemo)
                }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onChange(of: deviceManager.isConnected) {
            if deviceManager.isConnected {
                podDiscovery.status = .idle
                // Auto-dismiss welcome screen when connection succeeds
                sensorStream.connect()
            }
        }
        .onChange(of: sensorStream.latestDeviceStatus?.ts) { _, _ in
            if !isDemo, let status = sensorStream.latestDeviceStatus {
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
        settingsManager.switchBackend(client)
        scheduleManager.switchBackend(client)
        metricsManager.switchBackend(client)
        statusManager.switchBackend(client)
        sensorStream.disconnect()
        sensorStream.connect()
    }
}
