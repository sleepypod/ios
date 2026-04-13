import SwiftUI

/// Unified active curve — either from a run-once session or today's recurring schedule.
struct ActiveCurve: Identifiable {
    enum Source { case runOnce, schedule }
    let id: String
    let source: Source
    let session: RunOnceSession? // non-nil for run-once
    let setPoints: [RunOnceSetPoint]
    let wakeTime: String
}

struct TempScreen: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(ScheduleManager.self) private var scheduleManager

    @State private var bgPulse = false
    @State private var activeCurve: ActiveCurve?

    private func stopCurve() {
        guard let curve = activeCurve else { return }
        let side = deviceManager.selectedSide.primarySide

        if curve.source == .runOnce {
            Task {
                let api = APIBackend.current.createClient()
                try? await api.cancelRunOnce(side: side)
                let powerOff = SideStatusUpdate(isOn: false)
                var update = DeviceStatusUpdate()
                if side == .left { update.left = powerOff } else { update.right = powerOff }
                try? await api.updateDeviceStatus(update)
                await deviceManager.fetchStatus()
                withAnimation { activeCurve = nil }
            }
        }
    }

    private func fetchActiveCurve() async {
        let side = deviceManager.selectedSide.primarySide

        // 1. Check for run-once session (overrides recurring)
        if let session = try? await APIBackend.current.createClient().getActiveRunOnce(side: side) {
            activeCurve = ActiveCurve(
                id: "runonce-\(session.id)",
                source: .runOnce,
                session: session,
                setPoints: session.setPoints,
                wakeTime: session.wakeTime
            )
            return
        }

        // 2. Fall back to today's recurring schedule
        if let schedules = scheduleManager.schedules {
            let today = currentDayOfWeek()
            let sideSchedule = schedules.schedule(for: side)
            let daily = sideSchedule[today]

            if !daily.temperatures.isEmpty {
                // Sort by offset-from-bedtime so an overnight curve renders left-to-right
                // as evening → morning. String-sorting ("03:00" < "22:00") would put the
                // wake-side points first and push bedtime points ~20h into the chart.
                let bedtime = daily.power.enabled ? daily.power.on : "22:00"
                let bedMin = clockMinutesOfDay(bedtime)
                let points = daily.temperatures
                    .sorted { lhs, rhs in
                        offsetFromBedtime(lhs.key, bedtime: bedMin)
                            < offsetFromBedtime(rhs.key, bedtime: bedMin)
                    }
                    .map { RunOnceSetPoint(time: $0.key, temperature: Double($0.value)) }
                let wake = daily.power.enabled ? daily.power.off : "07:00"
                activeCurve = ActiveCurve(
                    id: "schedule-\(side.rawValue)-\(today.rawValue)",
                    source: .schedule,
                    session: nil,
                    setPoints: points,
                    wakeTime: wake
                )
                return
            }
        }

        activeCurve = nil
    }

    private func currentDayOfWeek() -> DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar weekday: 1=Sunday, 2=Monday, ...
        let days: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return days[weekday - 1]
    }

    private func clockMinutesOfDay(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return 0 }
        return h * 60 + m
    }

    private func offsetFromBedtime(_ time: String, bedtime: Int) -> Int {
        (clockMinutesOfDay(time) - bedtime + 1440) % 1440
    }

    /// Short "Just now" / "12s ago" / "2m ago" label for the last-updated indicator.
    static func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }

    private var sideName: String {
        settingsManager.sideName(for: deviceManager.selectedSide.primarySide)
    }

    private var ambientColor: Color {
        guard deviceManager.isConnected, deviceManager.isOn else { return .clear }
        let status = deviceManager.currentSideStatus
        let target = status?.targetTemperatureF ?? 80
        let current = status?.currentTemperatureF ?? 80
        return TempColor.forDelta(target: target, current: current)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full-screen ambient glow
                if deviceManager.isConnected && deviceManager.isOn {
                    RadialGradient(
                        colors: [
                            ambientColor.opacity(bgPulse ? 0.3 : 0.18),
                            ambientColor.opacity(bgPulse ? 0.12 : 0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: geo.size.height * (bgPulse ? 0.75 : 0.65)
                    )
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: bgPulse)
                    .animation(.easeInOut(duration: 1.0), value: ambientColor)
                    .onAppear { bgPulse = true }
                }

                if deviceManager.isConnected {
                    VStack(spacing: 0) {
                        // Top bar — name + priming + last-updated + settings gear
                        HStack(spacing: 8) {
                            Text(sideName)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Theme.textSecondary)
                            if deviceManager.deviceStatus?.isPriming == true {
                                PrimingIndicator()
                            }
                            if let lastUpdated = deviceManager.lastUpdated {
                                TimelineView(.periodic(from: .now, by: 15.0)) { _ in
                                    Text("• \(Self.relativeTime(from: lastUpdated))")
                                        .font(.caption2)
                                        .foregroundColor(Theme.textMuted)
                                }
                            }
                            Spacer()
                            UserSelectorView()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    ScrollView {
                        VStack(spacing: 0) {
                            // Side selector — below toolbar with a gap
                            SideSelectorView()
                                .padding(.horizontal, 16)
                                .padding(.top, 12)

                            // Alerts
                            VStack(spacing: 8) {
                                if deviceManager.isAlarmActive, let side = deviceManager.alarmSide {
                                    AlarmBanner(side: side) {
                                        deviceManager.stopAlarm()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)

                            Spacer(minLength: 0)

                            // Dial + controls — vertically centered in remaining space
                            VStack(spacing: 20) {
                                TemperatureDialView()
                                    .onTapGesture {
                                        Haptics.medium()
                                        deviceManager.togglePower()
                                    }
                                    .padding(.top, 8)

                                if let curve = activeCurve {
                                    RunOnceActiveBanner(
                                        session: curve.session ?? RunOnceSession(
                                            id: 0,
                                            side: deviceManager.selectedSide.primarySide.rawValue,
                                            setPoints: curve.setPoints,
                                            wakeTime: curve.wakeTime,
                                            startedAt: Int(Date().timeIntervalSince1970),
                                            expiresAt: Int(Date().timeIntervalSince1970) + 28800,
                                            status: "active"
                                        ),
                                        onCancel: { stopCurve() },
                                        compact: true,
                                        isSchedule: curve.source == .schedule
                                    )
                                    .id(curve.id)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                } else {
                                    TempControlsView()
                                        .transition(.opacity)
                                }

                                EnvironmentInfoView()
                            }
                            .animation(.easeInOut(duration: 0.3), value: activeCurve?.id)
                            .padding(.horizontal, 16)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: geo.size.height - 60)
                    }
                    .refreshable {
                        await deviceManager.fetchStatus()
                        await fetchActiveCurve()
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: deviceManager.selectedSide) {
                        activeCurve = nil
                        Task { await fetchActiveCurve() }
                    }
                    // .task fires once per view identity (survives tab switches);
                    // .onAppear would re-fire every time the Temp tab is re-shown.
                    .task { await fetchActiveCurve() }
                    } // VStack
                } else {
                    DisconnectedTabView(tab: "Temp")
                }
            }
        }
        .background(Theme.background)
    }
}

// MARK: - Alert Banner

enum AlertBannerStyle {
    case info, warning

    var bgGradient: LinearGradient {
        switch self {
        case .info:
            LinearGradient(colors: [Color(hex: "1e3c50").opacity(0.8), Color(hex: "143246").opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warning:
            LinearGradient(colors: [Color(hex: "503c1e").opacity(0.8), Color(hex: "3c2d14").opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var borderColor: Color {
        switch self {
        case .info: Color(hex: "468ca0").opacity(0.4)
        case .warning: Color(hex: "b48c3c").opacity(0.4)
        }
    }

    var textColor: Color {
        switch self {
        case .info: Color(hex: "8ecfcf")
        case .warning: Color(hex: "e0c080")
        }
    }
}

private struct AlertBanner: View {
    let icon: String
    let title: String
    let message: String
    let style: AlertBannerStyle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(style.textColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(style.textColor)
                Text(message)
                    .font(.caption)
                    .foregroundColor(style.textColor.opacity(0.7))
            }
            Spacer()
        }
        .padding(12)
        .background(style.bgGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Alarm Banner

private struct AlarmBanner: View {
    let side: Side
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .foregroundColor(Color(hex: "e0c080"))
            VStack(alignment: .leading, spacing: 2) {
                Text("Alarm Active")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color(hex: "e0c080"))
                Text("\(side.displayName) side alarm is vibrating")
                    .font(.caption)
                    .foregroundColor(Color(hex: "e0c080").opacity(0.7))
            }
            Spacer()
            Button {
                Haptics.medium()
                Task {
                    _ = try? await APIBackend.current.createClient().snoozeAlarm(side: side, duration: 300)
                }
            } label: {
                Text("Snooze")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(hex: "e0c080"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "e0c080").opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button("Stop") {
                Haptics.heavy()
                onStop()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.error)
            .clipShape(Capsule())
        }
        .padding(12)
        .background(
            LinearGradient(colors: [Color(hex: "503c1e").opacity(0.8), Color(hex: "3c2d14").opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "b48c3c").opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Environment Info

private struct EnvironmentInfoView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var ambientLight: AmbientLightReading?

    private var ambientTempF: Int {
        deviceManager.currentSideStatus?.currentTemperatureF ?? 0
    }

    private var autoOffText: String? {
        guard let status = deviceManager.currentSideStatus,
              status.isOn,
              status.secondsRemaining > 0 else { return nil }
        let hours = status.secondsRemaining / 3600
        let minutes = (status.secondsRemaining % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 20) {
            if ambientTempF > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    Text("\(TemperatureConversion.displayTemp(ambientTempF, format: settingsManager.temperatureFormat))  Inside")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }

            if let autoOff = autoOffText {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    Text(autoOff)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }

            if let light = ambientLight {
                HStack(spacing: 6) {
                    Image(systemName: light.lux < 10 ? "moon.fill" : "sun.max.fill")
                        .font(.caption)
                        .foregroundColor(light.lux < 10 ? Theme.purple : Theme.amber)
                    Text("\(Int(light.lux)) lux")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .task {
            ambientLight = try? await APIBackend.current.createClient().getAmbientLightLatest()
        }
    }
}
