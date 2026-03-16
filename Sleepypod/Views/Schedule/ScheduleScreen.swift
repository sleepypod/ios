import SwiftUI

struct ScheduleScreen: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var showAdvanced = false
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Side selector
                ScheduleSideSelectorView()

                // Day selector
                DaySelectorView()

                // Smart curve
                SmartCurveView()

                // Schedule toggle
                scheduleToggle

                // Manual set points (advanced)
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                } label: {
                    HStack {
                        Text("Manual Set Points")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                            .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                // Phase blocks
                if scheduleManager.schedules != nil {
                    VStack(spacing: 12) {
                        ForEach(scheduleManager.phases) { phase in
                            PhaseBlockView(phase: phase)
                        }
                    }
                } else if scheduleManager.isLoading {
                    LoadingView(message: "Loading schedule…")
                } else {
                    Text("No schedule data")
                        .foregroundColor(Theme.textSecondary)
                        .padding(40)
                }

                // Clear schedule
                if scheduleManager.schedules != nil && !scheduleManager.phases.isEmpty {
                    Button {
                        Haptics.medium()
                        showClearConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Clear Schedule")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(Theme.error)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .task {
            await scheduleManager.fetchSchedules()
        }
        .alert("Clear Schedule", isPresented: $showClearConfirm) {
            Button("Clear Selected Days", role: .destructive) {
                Task { await clearSchedule() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all temperature, power, and alarm schedules for the selected days.")
        }
    }

    private func clearSchedule() async {
        guard var schedules = scheduleManager.schedules else { return }
        let side = scheduleManager.selectedSide.primarySide
        let emptyDaily = DailySchedule(
            temperatures: [:],
            alarm: AlarmSchedule(vibrationIntensity: 50, vibrationPattern: .rise, duration: 30, time: "07:00", enabled: false, alarmTemperature: 80),
            power: PowerSchedule(on: "22:00", off: "07:00", onTemperature: 75, enabled: false)
        )

        for day in scheduleManager.selectedDays {
            var sideSchedule = schedules.schedule(for: side)
            sideSchedule[day] = emptyDaily
            schedules.setSchedule(sideSchedule, for: side)

            if scheduleManager.selectedSide == .both {
                var other = schedules.schedule(for: side == .left ? .right : .left)
                other[day] = emptyDaily
                schedules.setSchedule(other, for: side == .left ? .right : .left)
            }
        }

        scheduleManager.schedules = schedules
        do {
            let api = APIBackend.current.createClient()
            scheduleManager.schedules = try await api.updateSchedules(schedules)
            Haptics.heavy()
        } catch {
            Log.general.error("Failed to clear schedule: \(error)")
        }
    }

    private var scheduleToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule Active")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Text("Automatically adjust temperature")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { scheduleManager.currentDailySchedule?.power.enabled ?? false },
                set: { _ in Haptics.medium(); Task { await scheduleManager.togglePowerSchedule() } }
            ))
                .tint(Theme.cooling)
                .labelsHidden()
        }
        .cardStyle()
    }
}

// MARK: - Schedule Side Selector

private struct ScheduleSideSelectorView: View {
    @Environment(ScheduleManager.self) private var scheduleManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach([SideSelection.left, .right, .both], id: \.self) { selection in
                let isSelected = scheduleManager.selectedSide == selection
                Button {
                    Haptics.tap()
                    scheduleManager.selectedSide = selection
                } label: {
                    Text(label(for: selection))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color(hex: "1e2a3a") : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func label(for selection: SideSelection) -> String {
        switch selection {
        case .left: "Left"
        case .right: "Right"
        case .both: "Both"
        }
    }
}

extension SideSelection: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .left: hasher.combine("left")
        case .right: hasher.combine("right")
        case .both: hasher.combine("both")
        }
    }
}
