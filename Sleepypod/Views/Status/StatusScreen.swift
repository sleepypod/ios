import SwiftUI

struct StatusScreen: View {
    @Environment(StatusManager.self) private var statusManager
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PodDiscovery.self) private var podDiscovery
    @Environment(SensorStreamService.self) private var sensor

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Health circle
                HealthCircleView()

                // Service categories + hardware details
                let cats = statusManager.categories(schedules: scheduleManager.schedules)
                if cats.isEmpty && statusManager.isLoading {
                    LoadingView(message: "Checking services…")
                } else {
                    ForEach(cats) { category in
                        ServiceCategoryView(category: category) { service in
                            Task { await statusManager.retryService(service) }
                        }

                        // Insert hardware-related cards after the Hardware category
                        if category.name == "Hardware" {
                            processingCard
                            calibrationCard
                            networkDiscoveryCard
                        }
                    }
                }

                // Systemd services
                if !statusManager.logSources.isEmpty {
                    servicesCard
                }

                // Logs
                LogsView()

                // Sensor console (firmware logs + raw frames)
                FirmwareLogConsoleView(
                    logs: sensor.firmwareLogs,
                    recentFrames: sensor.recentFrames,
                    onClear: { sensor.clearLogs() }
                )

                // Last updated
                if let lastUpdated = statusManager.lastUpdated {
                    Text("Last updated: \(lastUpdated, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .task {
            statusManager.startPolling()
            await scheduleManager.fetchSchedules()
            // Fetch calibration on load
            let api = APIBackend.current.createClient()
            leftCalibration = try? await api.getCalibrationStatus(side: .left)
            rightCalibration = try? await api.getCalibrationStatus(side: .right)
        }
    }

    // MARK: - Calibration

    @State private var isCalibrationExpanded = false
    @State private var leftCalibration: CalibrationStatus?
    @State private var rightCalibration: CalibrationStatus?
    @State private var showCalibrationSheet = false

    private var calHealthy: Int {
        func goodSensors(_ cal: CalibrationStatus?) -> Int {
            guard let cal else { return 0 }
            return cal.sensors.filter { $0.status == "completed" && ($0.qualityScore ?? 0) >= 0.5 }.count
        }
        return goodSensors(leftCalibration) + goodSensors(rightCalibration)
    }

    private var calibrationCard: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) { isCalibrationExpanded.toggle() }
                if isCalibrationExpanded && leftCalibration == nil {
                    Task {
                        let api = APIBackend.current.createClient()
                        leftCalibration = try? await api.getCalibrationStatus(side: .left)
                        rightCalibration = try? await api.getCalibrationStatus(side: .right)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tuningfork")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.cyan)
                        .frame(width: 32, height: 32)
                        .background(Theme.cyan.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("Calibration")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)

                    Spacer()

                    HStack(spacing: 4) {
                        let total = 6
                        let allGood = calHealthy == total
                        Image(systemName: allGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(allGood ? Theme.healthy : Theme.amber)
                        Text("\(calHealthy)/\(total)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "222222"))
                    .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(isCalibrationExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isCalibrationExpanded {
                Divider().background(Theme.cardBorder).padding(.vertical, 8)

                VStack(spacing: 8) {
                    if let left = leftCalibration {
                        sideCalibrationSection("Left", cal: left)
                    }
                    if let right = rightCalibration {
                        Divider().background(Theme.cardBorder).padding(.vertical, 4)
                        sideCalibrationSection("Right", cal: right)
                    }
                    if leftCalibration == nil {
                        HStack {
                            ProgressView().tint(Theme.accent).scaleEffect(0.7)
                            Text("Loading…").font(.caption).foregroundColor(Theme.textMuted)
                        }
                    }

                    // Single calibration button
                    Button {
                        Haptics.medium()
                        showCalibrationSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tuningfork")
                            Text("Run Calibration")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.cyan.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showCalibrationSheet) {
            CalibrationSheet(
                onComplete: {
                    Task {
                        let api = APIBackend.current.createClient()
                        leftCalibration = try? await api.getCalibrationStatus(side: .left)
                        rightCalibration = try? await api.getCalibrationStatus(side: .right)
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func sideCalibrationSection(_ side: String, cal: CalibrationStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(side) Side")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.accent)

            ForEach(cal.sensors, id: \.id) { sensor in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: sensorIcon(sensor))
                            .font(.system(size: 11))
                            .foregroundColor(sensorColor(sensor))
                        Text(sensorDisplayName(sensor.sensorType))
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                        if let score = sensor.qualityScore {
                            let pct = score * 100
                            Text(String(format: "%.0f%%", pct))
                                .font(.caption2.weight(.medium).monospaced())
                                .foregroundColor(qualityColor(pct))
                        }
                        if let samples = sensor.samplesUsed {
                            Text("\(samples) samples")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                    if let err = sensor.errorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundColor(Theme.error)
                            .padding(.leading, 19)
                    }
                }
            }
        }
    }

    private func sensorDisplayName(_ type: String) -> String {
        switch type.lowercased() {
        case "piezo": "Piezo (heartbeat)"
        case "temperature": "Temperature (body heat)"
        case "capacitance": "Capacitance (presence)"
        default: type.capitalized
        }
    }

    private func qualityColor(_ pct: Double) -> Color {
        if pct >= 70 { return Theme.healthy }
        if pct >= 40 { return Theme.amber }
        if pct > 0 { return Theme.error }
        return Theme.textMuted
    }

    private func sensorIcon(_ sensor: CalibrationSensor) -> String {
        if sensor.status != "completed" { return "xmark.circle.fill" }
        let q = (sensor.qualityScore ?? 0) * 100
        if q >= 50 { return "checkmark.circle.fill" }
        if q > 0 { return "exclamationmark.circle.fill" }
        return "exclamationmark.circle.fill"
    }

    private func sensorColor(_ sensor: CalibrationSensor) -> Color {
        if sensor.status != "completed" { return Theme.error }
        return qualityColor((sensor.qualityScore ?? 0) * 100)
    }

    // MARK: - Processing

    @State private var isMLExpanded = false

    private var processingCard: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) { isMLExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.purple)
                        .frame(width: 32, height: 32)
                        .background(Theme.purple.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("On-Device Intelligence")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text("Core ML pipeline")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(Theme.healthy)
                        Text("3/3")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "222222"))
                    .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(isMLExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isMLExpanded {
                Divider().background(Theme.cardBorder).padding(.vertical, 8)

                VStack(spacing: 6) {
                    modelRow(
                        name: "Sleep Stage Classifier",
                        type: "Rule-based",
                        status: "Active",
                        icon: "moon.zzz.fill",
                        color: Theme.purple
                    )
                    modelRow(
                        name: "Outlier Filter",
                        type: "Boundary (HR>200, HRV>300)",
                        status: "Active",
                        icon: "line.3.crossed.swirl.circle.fill",
                        color: Theme.accent
                    )
                    modelRow(
                        name: "HRV Trend Analysis",
                        type: "EMA baseline comparison",
                        status: "Active",
                        icon: "chart.xyaxis.line",
                        color: Theme.healthy
                    )

                    Divider().background(Theme.cardBorder).padding(.vertical, 4)

                    // Future models
                    modelRow(
                        name: "Sleep Stage CNN",
                        type: "Core ML · Requires training data",
                        status: "Not trained",
                        icon: "brain.head.profile.fill",
                        color: Theme.textMuted
                    )
                    modelRow(
                        name: "Anomaly Detection",
                        type: "Core ML · Requires baseline",
                        status: "Not trained",
                        icon: "exclamationmark.bubble.fill",
                        color: Theme.textMuted
                    )
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func modelRow(name: String, type: String, status: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption)
                    .foregroundColor(.white)
                Text(type)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            Text(status)
                .font(.caption2)
                .foregroundColor(color == Theme.textMuted ? Theme.textMuted : Theme.healthy)
        }
    }

    // MARK: - Services

    @State private var servicesExpanded = false

    private var servicesCard: some View {
        let sources = statusManager.logSources
        let activeCount = sources.filter(\.active).count
        let allHealthy = activeCount == sources.count

        return VStack(spacing: 0) {
            // Header — matches ServiceCategoryView pattern
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    servicesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.cyan)
                        .frame(width: 32, height: 32)
                        .background(Theme.cyan.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Services")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text("Systemd service units")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: allHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(allHealthy ? Theme.healthy : Theme.amber)
                        Text("\(activeCount)/\(sources.count)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "222222"))
                    .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(servicesExpanded ? 90 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Expanded — checkmark rows
            if servicesExpanded {
                Divider().background(Theme.cardBorder)

                VStack(spacing: 0) {
                    ForEach(sources) { source in
                        HStack(spacing: 10) {
                            Image(systemName: source.active ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(source.active ? Theme.healthy : Theme.error)
                            Text(source.name)
                                .font(.caption)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Network Discovery

    @State private var isDiscoveryExpanded = false

    private var networkDiscoveryCard: some View {
        VStack(spacing: 0) {
            // Header — matches ServiceCategoryView style
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDiscoveryExpanded.toggle()
                }
                // Only scan when disconnected — don't disrupt active connection
                if isDiscoveryExpanded && !deviceManager.isConnected && !podDiscovery.isSearching {
                    podDiscovery.startBrowsing()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Network Discovery")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text("mDNS auto-discovery")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    // Status badge — matches ServiceCategoryView pattern
                    HStack(spacing: 4) {
                        Image(systemName: deviceManager.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(deviceManager.isConnected ? Theme.healthy : Theme.amber)
                        Text(deviceManager.isConnected ? "1/1" : "0/1")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "222222"))
                    .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(isDiscoveryExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isDiscoveryExpanded {
                Divider()
                    .background(Theme.cardBorder)
                    .padding(.vertical, 8)

                VStack(spacing: 8) {
                    // Connected pod info
                    if deviceManager.isConnected {
                        HStack(spacing: 10) {
                            Image("WelcomeLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(podDiscovery.connectedPodName ?? podDiscovery.discoveredPods.first?.name ?? settingsManager.podIP)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Text(settingsManager.podIP)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.healthy)
                        }
                        .padding(.vertical, 4)
                    }

                    // Discovered pods from scan
                    if podDiscovery.isSearching {
                        HStack(spacing: 8) {
                            ProgressView().tint(Theme.accent).scaleEffect(0.7)
                            Text("Scanning network…")
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                        }
                        .padding(.vertical, 4)
                    } else if !podDiscovery.discoveredPods.isEmpty {
                        ForEach(podDiscovery.discoveredPods) { pod in
                            HStack(spacing: 10) {
                                Image("WelcomeLogo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(pod.name)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Spacer()
                                Text("Port \(pod.port)")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.vertical, 2)
                        }
                    } else if !deviceManager.isConnected {
                        Text("No Sleepypod found on network")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

}
