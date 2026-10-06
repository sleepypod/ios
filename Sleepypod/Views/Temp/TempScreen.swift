import SwiftUI

/// Unified active curve — either from a run-once session or today's recurring schedule.
struct ActiveCurve: Identifiable {
    enum Source { case runOnce, schedule }
    let id: String
    let source: Source
    let session: RunOnceSession? // non-nil for run-once
    let setPoints: [RunOnceSetPoint]
    let wakeTime: String
    let bedtime: String
}

struct TempScreen: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(ScheduleManager.self) private var scheduleManager

    @Environment(SensorStreamService.self) private var sensor
    @State private var curveError: String?
    @State private var activeCurve: ActiveCurve?

    private func stopCurve() {
        guard let curve = activeCurve else { return }
        let side = deviceManager.selectedSide.primarySide

        if curve.source == .runOnce {
            Task {
                let api = APIBackend.current.createClient()
                do {
                    try await api.cancelRunOnce(side: side)
                    let powerOff = SideStatusUpdate(isOn: false)
                    var update = DeviceStatusUpdate()
                    if side == .left { update.left = powerOff } else { update.right = powerOff }
                    try await api.updateDeviceStatus(update)
                    await deviceManager.fetchStatus()
                    curveError = nil
                    withAnimation { activeCurve = nil }
                } catch { curveError = error.localizedDescription }

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
                wakeTime: session.wakeTime,
                bedtime: session.setPoints.first?.time ?? "22:00"
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
                    wakeTime: wake,
                    bedtime: bedtime
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
        if deviceManager.isLinked { return "\(settingsManager.leftName) + \(settingsManager.rightName)" }
        return settingsManager.sideName(for: deviceManager.selectedSide.primarySide)
    }

    var body: some View {
        NavigationStack {
            Group {
                if deviceManager.isConnected {
                    ScrollView {
                        VStack(spacing: 0) {
                            SideSelectorView()
                            TemperatureDialView().padding(.top, 28)
                            TempControlsView().padding(.top, 14)
                            environmentLine.padding(.top, 26)
                            VStack(spacing: 12) {
                                if let curveError {
                                    Text(curveError).font(.footnote).foregroundStyle(Theme.amber)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if deviceManager.isAlarmActive, let side = deviceManager.alarmSide { alarmCard(side) }
                                if let curve = activeCurve {
                                    if let session = curve.session {
                                        RunOnceActiveBanner(session: session, onCancel: stopCurve, compact: true)
                                    } else {
                                        tonightCard(curve)
                                    }
                                }
                            }
                            .padding(.top, 24)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    .refreshable { await deviceManager.fetchStatus(); await fetchActiveCurve() }
                } else {
                    DisconnectedTabView(tab: "Temp")
                }
            }
            .background(Theme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .settingsToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { header }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
        .task {
            await settingsManager.fetchSettings()
            await scheduleManager.fetchSchedules()
            await fetchActiveCurve()
            if deviceManager.isConnected { sensor.connect() }
        }
        .task(id: deviceManager.selectedSide) { await fetchActiveCurve() }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTempTab)) { _ in Task { await fetchActiveCurve() } }
    }

    private var header: some View {
        let side = deviceManager.selectedSide.primarySide
        let occupied = deviceManager.isLinked
            ? (sensor.isOccupied(side: .left) || sensor.isOccupied(side: .right))
            : sensor.isOccupied(side: side)
        let place = deviceManager.isLinked ? "BOTH" : side.rawValue.uppercased()
        return VStack(alignment: .leading, spacing: 3) {
            Text(sideName).font(.title2.bold()).tracking(-0.3).lineLimit(1)
            HStack(spacing: 6) {
                if occupied { StatusDot() }
                Eyebrow("\(place) · \(occupied ? "IN BED" : "AWAY")")
                if APIBackend.current.isDemo { Eyebrow("· DEMO", color: Theme.amber) }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private var environmentLine: some View {
        HStack(spacing: 18) {
            let temps = deviceManager.selectedSide.primarySide == .left ? sensor.leftTemps : sensor.rightTemps
            if let ambient = temps?.amb, ambient.isFinite, ambient > -100 {
                let format = settingsManager.temperatureFormat == .relative ? .fahrenheit : settingsManager.temperatureFormat
                Label {
                    Text("\(TemperatureConversion.displayTemp(Int((ambient * 9 / 5 + 32).rounded()), format: format)) inside")
                } icon: { Image(systemName: "house") }
            }
            if let status = deviceManager.currentSideStatus, status.isOn, status.secondsRemaining > 0 {
                Label { Text(DisplayTime.duration(status.secondsRemaining)) } icon: { Image(systemName: "timer") }
                    .accessibilityLabel("Turns off in \(DisplayTime.duration(status.secondsRemaining))")
            }
        }
        .labelStyle(EnvironmentLabelStyle())
        .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
        .frame(minHeight: 16)
    }

    private func tonightCard(_ curve: ActiveCurve) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Eyebrow("TONIGHT · \(profileName(curve.setPoints).uppercased())")
                    Spacer(minLength: 8)
                    range(curve)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("TONIGHT · \(profileName(curve.setPoints).uppercased())")
                    range(curve)
                }
            }
            TemperatureCurve(points: curve.setPoints, bedtime: curve.bedtime, wake: curve.wakeTime, compact: true)
        }
        .cardStyle()
    }

    private func range(_ curve: ActiveCurve) -> some View {
        Text("\(DisplayTime.clock(curve.bedtime)) → \(DisplayTime.clock(curve.wakeTime))")
            .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
    }

    private func alarmCard(_ side: Side) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm").foregroundStyle(Theme.amber)
            Text("Alarm").font(.subheadline.weight(.semibold))
            Spacer()
            Button("Snooze") {
                Task { _ = try? await APIBackend.current.createClient().snoozeAlarm(side: side, duration: 300) }
            }
            .font(.subheadline.weight(.semibold))
            Button("Stop") { deviceManager.stopAlarm() }.font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.plain)
        .cardStyle(vertical: 14)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.amber, lineWidth: 1))
    }

    private func profileName(_ points: [RunOnceSetPoint]) -> String {
        let values = points.map { Int($0.temperature) }.sorted()
        return SleepProfile.allCases.first { $0.temperatures(for: values.count).sorted() == values }?.rawValue ?? "Custom"
    }
}

private struct EnvironmentLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 12)); configuration.title }
    }
}
