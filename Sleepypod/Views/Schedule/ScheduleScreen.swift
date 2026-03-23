import SwiftUI

struct ScheduleScreen: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var showAdvanced = false
    @State private var showClearConfirm = false
    @State private var showAICurve = false
    @State private var aiCurveStartPage = 0
    @State private var showCurvePicker = false
    @State private var savedTemplates: [CurveTemplate] = []
    @State private var activeRunOnce: RunOnceSession?

    private func fetchActiveRunOnce() async {
        do {
            let api = APIBackend.current.createClient()
            activeRunOnce = try await api.getActiveRunOnce(side: scheduleManager.selectedSide.primarySide)
        } catch {
            activeRunOnce = nil
        }
    }

    /// Derives a display name for the currently-active curve by matching
    /// the schedule's temperature set-points against known profiles and
    /// saved templates.  Returns "None" when nothing matches.
    private var currentCurveName: String {
        guard let daily = scheduleManager.currentDailySchedule,
              !daily.temperatures.isEmpty else {
            return "None"
        }

        let temps = daily.temperatures.values.sorted()
        let count = temps.count

        // Check built-in SleepProfile matches
        for profile in SleepProfile.allCases {
            if profile.temperatures(for: count) == temps {
                return profile.rawValue
            }
        }

        // Check saved templates
        for template in savedTemplates {
            let templateTemps = template.points.values.sorted()
            if templateTemps == temps {
                return template.name
            }
        }

        return "Custom"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Side selector
                ScheduleSideSelectorView()

                // Active run-once banner
                if let session = activeRunOnce {
                    RunOnceActiveBanner(session: session) {
                        let side = scheduleManager.selectedSide.primarySide
                        Task {
                            let api = APIBackend.current.createClient()
                            try? await api.cancelRunOnce(side: side)
                            let powerOff = SideStatusUpdate(isOn: false)
                            var update = DeviceStatusUpdate()
                            if side == .left { update.left = powerOff } else { update.right = powerOff }
                            try? await api.updateDeviceStatus(update)
                            withAnimation { activeRunOnce = nil }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Schedule toggle — at the top for quick access
                scheduleToggle

                // Day selector
                DaySelectorView()

                // Smart curve (Custom button opens curve picker)
                SmartCurveView(showCurvePicker: $showCurvePicker)

                // Manual Controls — phase set points, power schedule, alarm schedule
                if scheduleManager.schedules != nil {
                    VStack(spacing: 10) {
                        Button {
                            Haptics.light()
                            withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                        } label: {
                            HStack {
                                Text("Manual Controls")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(Theme.textSecondary)
                                Text("Set points, power, alarm")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textMuted)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textMuted)
                                    .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                            }
                        }
                        .buttonStyle(.plain)

                        if showAdvanced {
                            // Horizontal scrolling phase cards
                            if !scheduleManager.phases.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(scheduleManager.phases) { phase in
                                            PhaseBlockCompactView(phase: phase)
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                            }

                            // Power schedule card
                            if let power = scheduleManager.currentDailySchedule?.power {
                                PowerScheduleCompactView(power: power)
                            }

                            // Alarm schedule card
                            if let alarm = scheduleManager.currentDailySchedule?.alarm {
                                AlarmScheduleCompactView(alarm: alarm)
                            }

                            // Clear schedule
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
                        }
                    }
                } else if scheduleManager.isLoading {
                    LoadingView(message: "Loading schedule\u{2026}")
                } else if scheduleManager.schedules == nil {
                    Text("No schedule data")
                        .foregroundColor(Theme.textSecondary)
                        .padding(40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .animation(.easeInOut(duration: 0.3), value: activeRunOnce != nil)
        .background(Theme.background)
        .task {
            await scheduleManager.fetchSchedules()
        }
        .onAppear {
            savedTemplates = CurveTemplate.loadAll()
            Task { await fetchActiveRunOnce() }
        }
        .task(id: scheduleManager.selectedSide) {
            await fetchActiveRunOnce()
        }
        .sheet(isPresented: $showCurvePicker, onDismiss: {
            savedTemplates = CurveTemplate.loadAll()
        }) {
            CurvePickerSheet(
                savedTemplates: $savedTemplates,
                onApplyProfile: { profile in
                    Task { await scheduleManager.applyProfile(profile) }
                    Haptics.success()
                },
                onApplyTemplate: { template in
                    applyTemplate(template)
                },
                onDeleteTemplate: { name in
                    CurveTemplate.delete(named: name)
                    savedTemplates = CurveTemplate.loadAll()
                },
                onDesignYourOwn: {
                    showCurvePicker = false
                    aiCurveStartPage = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAICurve = true
                    }
                },
                onImport: {
                    showCurvePicker = false
                    aiCurveStartPage = 2
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAICurve = true
                    }
                },
                currentCurveName: currentCurveName
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAICurve, onDismiss: {
            savedTemplates = CurveTemplate.loadAll()
        }) {
            AICurvePromptView(startPage: aiCurveStartPage)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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

    // MARK: - Apply Template

    private func applyTemplate(_ template: CurveTemplate) {
        Task {
            guard var schedules = scheduleManager.schedules else { return }
            let side = scheduleManager.selectedSide.primarySide

            for day in scheduleManager.selectedDays {
                var sideSchedule = schedules.schedule(for: side)
                var daily = sideSchedule[day]
                daily.temperatures = template.points
                daily.power.on = template.bedtime
                daily.power.off = template.wake
                daily.power.enabled = true
                daily.alarm.time = template.wake
                daily.alarm.enabled = true
                sideSchedule[day] = daily
                schedules.setSchedule(sideSchedule, for: side)

                if scheduleManager.selectedSide == .both {
                    var other = schedules.schedule(for: side == .left ? .right : .left)
                    other[day] = daily
                    schedules.setSchedule(other, for: side == .left ? .right : .left)
                }
            }

            scheduleManager.schedules = schedules
            do {
                let api = APIBackend.current.createClient()
                scheduleManager.schedules = try await api.updateSchedules(schedules, days: scheduleManager.selectedDays)
                Haptics.success()
            } catch {
                Log.general.error("Failed to apply template: \(error)")
            }
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

        let previous = scheduleManager.schedules
        scheduleManager.schedules = schedules
        do {
            let api = APIBackend.current.createClient()
            scheduleManager.schedules = try await api.updateSchedules(schedules, days: scheduleManager.selectedDays)
            Haptics.heavy()
        } catch {
            scheduleManager.schedules = previous
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

// MARK: - Curve Picker Sheet

private struct CurvePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var savedTemplates: [CurveTemplate]

    let onApplyProfile: (SleepProfile) -> Void
    let onApplyTemplate: (CurveTemplate) -> Void
    let onDeleteTemplate: (String) -> Void
    let onDesignYourOwn: () -> Void
    let onImport: () -> Void
    let currentCurveName: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: Custom Curves
                    if !savedTemplates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SAVED CURVES")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                                .tracking(1)
                                .padding(.horizontal, 4)

                            VStack(spacing: 2) {
                                ForEach(savedTemplates) { template in
                                    templateRow(template)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "moon.stars")
                                .font(.title2)
                                .foregroundColor(Theme.textMuted)
                            Text("No custom curves yet")
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                            Text("Design your own to get started")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }

                    // MARK: Actions
                    VStack(spacing: 8) {
                        // Design Your Own
                        Button {
                            Haptics.light()
                            onDesignYourOwn()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 16))
                                    .foregroundColor(Theme.accent)
                                    .frame(width: 28)
                                Text("Design Your Own")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(Theme.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // Import existing
                        Button {
                            Haptics.light()
                            onImport()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 16))
                                    .foregroundColor(Theme.textSecondary)
                                    .frame(width: 28)
                                Text("Already have one? Import")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(Theme.textSecondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Theme.background)
            .navigationTitle("Custom Curves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Profile Row

    private func profileRow(
        profile: SleepProfile,
        color: Color,
        subtitle: String,
        range: String
    ) -> some View {
        let isActive = currentCurveName == profile.rawValue

        return Button {
            Haptics.light()
            onApplyProfile(profile)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()

                Text(range)
                    .font(.caption.monospaced())
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isActive ? Theme.accent.opacity(0.08) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Template Row

    private func templateRow(_ template: CurveTemplate) -> some View {
        let temps = template.points.values.sorted()
        let lo = temps.first ?? 65
        let hi = temps.last ?? 85
        let isActive = currentCurveName == template.name

        return Button {
            Haptics.light()
            onApplyTemplate(template)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(template.bedtime) \u{2192} \(template.wake)")
                        .font(.caption.monospaced())
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()

                Text("\(lo)\u{2013}\(hi)\u{00B0}F")
                    .font(.caption.monospaced())
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isActive ? Theme.accent.opacity(0.08) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Haptics.light()
                onDeleteTemplate(template.name)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Power Schedule Compact Card

private struct PowerScheduleCompactView: View {
    let power: PowerSchedule
    @Environment(ScheduleManager.self) private var scheduleManager
    @State private var showEditSheet = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                showEditSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(power.enabled ? Theme.accent : Theme.textMuted)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Power Schedule")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            Label(power.on, systemImage: "moon.fill")
                                .font(.caption2.monospaced())
                                .foregroundColor(Theme.textSecondary)
                            Text("\u{2192}")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                            Label(power.off, systemImage: "sun.max.fill")
                                .font(.caption2.monospaced())
                                .foregroundColor(Theme.textSecondary)
                        }

                        Text("Start: \(power.onTemperature)\u{00B0}F")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { power.enabled },
                set: { _ in
                    Haptics.medium()
                    Task { await scheduleManager.togglePowerSchedule() }
                }
            ))
            .tint(Theme.cooling)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .sheet(isPresented: $showEditSheet) {
            PowerScheduleEditSheet(power: power)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Power Schedule Edit Sheet

private struct PowerScheduleEditSheet: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(\.dismiss) private var dismiss

    @State private var onTime: Date
    @State private var offTime: Date
    @State private var onTemperature: Int
    @State private var isSaving = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init(power: PowerSchedule) {
        let fmt = Self.timeFormatter
        _onTime = State(initialValue: fmt.date(from: power.on) ?? Date())
        _offTime = State(initialValue: fmt.date(from: power.off) ?? Date())
        _onTemperature = State(initialValue: power.onTemperature)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // On time
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Bedtime", systemImage: "moon.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.textSecondary)
                        DatePicker("", selection: $onTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(height: 100)
                            .clipped()
                    }

                    // Off time
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wake", systemImage: "sun.max.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.textSecondary)
                        DatePicker("", selection: $offTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(height: 100)
                            .clipped()
                    }

                    // On temperature
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Start Temperature", systemImage: "thermometer.medium")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(onTemperature)\u{00B0}F")
                                .font(.subheadline.weight(.medium).monospaced())
                                .foregroundColor(.white)
                        }
                        Stepper("", value: $onTemperature, in: 55...110)
                            .labelsHidden()
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Edit Power Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.accent)
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        let fmt = Self.timeFormatter
        let updated = PowerSchedule(
            on: fmt.string(from: onTime),
            off: fmt.string(from: offTime),
            onTemperature: onTemperature,
            enabled: true
        )
        isSaving = true
        Task {
            await scheduleManager.updatePowerSchedule(updated)
            Haptics.success()
            dismiss()
        }
    }
}

// MARK: - Alarm Schedule Compact Card

private struct AlarmScheduleCompactView: View {
    let alarm: AlarmSchedule
    @Environment(ScheduleManager.self) private var scheduleManager
    @State private var showEditSheet = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                showEditSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "alarm")
                        .font(.system(size: 14))
                        .foregroundColor(alarm.enabled ? Theme.accent : Theme.textMuted)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Alarm Schedule")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)

                        Text(alarm.time)
                            .font(.caption2.monospaced())
                            .foregroundColor(Theme.textSecondary)

                        HStack(spacing: 8) {
                            Text("Intensity: \(alarm.vibrationIntensity)%")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                            Text("\u{00B7}")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                            Text(alarm.vibrationPattern.rawValue.capitalized)
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                            Text("\u{00B7}")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                            Text("\(alarm.duration)s")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { alarm.enabled },
                set: { newValue in
                    Haptics.medium()
                    Task {
                        guard var schedules = scheduleManager.schedules else { return }
                        let previous = schedules
                        let side = scheduleManager.selectedSide.primarySide
                        for day in scheduleManager.selectedDays {
                            var sideSchedule = schedules.schedule(for: side)
                            var daily = sideSchedule[day]
                            daily.alarm.enabled = newValue
                            sideSchedule[day] = daily
                            schedules.setSchedule(sideSchedule, for: side)
                        }
                        scheduleManager.schedules = schedules
                        do {
                            let api = APIBackend.current.createClient()
                            scheduleManager.schedules = try await api.updateSchedules(schedules, days: scheduleManager.selectedDays)
                        } catch {
                            scheduleManager.schedules = previous
                            Log.general.error("Failed to toggle alarm: \(error)")
                        }
                    }
                }
            ))
            .tint(Theme.cooling)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .sheet(isPresented: $showEditSheet) {
            AlarmScheduleEditSheet(alarm: alarm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Alarm Schedule Edit Sheet

private struct AlarmScheduleEditSheet: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(\.dismiss) private var dismiss

    @State private var alarmTime: Date
    @State private var vibrationIntensity: Double
    @State private var vibrationPattern: VibrationPattern
    @State private var duration: Double
    @State private var alarmTemperature: Int
    @State private var isSaving = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init(alarm: AlarmSchedule) {
        let fmt = Self.timeFormatter
        _alarmTime = State(initialValue: fmt.date(from: alarm.time) ?? Date())
        _vibrationIntensity = State(initialValue: Double(alarm.vibrationIntensity))
        _vibrationPattern = State(initialValue: alarm.vibrationPattern)
        _duration = State(initialValue: Double(alarm.duration))
        _alarmTemperature = State(initialValue: alarm.alarmTemperature)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Alarm time
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Alarm Time", systemImage: "alarm")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.textSecondary)
                        DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(height: 100)
                            .clipped()
                    }

                    // Vibration intensity
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Vibration Intensity", systemImage: "waveform.path")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(vibrationIntensity))%")
                                .font(.subheadline.weight(.medium).monospaced())
                                .foregroundColor(.white)
                        }
                        Slider(value: $vibrationIntensity, in: 1...100, step: 1)
                            .tint(Theme.accent)
                    }

                    // Pattern picker
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Pattern", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.textSecondary)
                        Picker("", selection: $vibrationPattern) {
                            Text("Rise").tag(VibrationPattern.rise)
                            Text("Double").tag(VibrationPattern.double)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Duration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Duration", systemImage: "timer")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(duration))s")
                                .font(.subheadline.weight(.medium).monospaced())
                                .foregroundColor(.white)
                        }
                        Slider(value: $duration, in: 1...180, step: 1)
                            .tint(Theme.accent)
                        HStack {
                            Text("1s")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                            Spacer()
                            Text("180s")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                        }
                    }

                    // Alarm temperature
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Alarm Temperature", systemImage: "thermometer.medium")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(alarmTemperature)\u{00B0}F")
                                .font(.subheadline.weight(.medium).monospaced())
                                .foregroundColor(.white)
                        }
                        Stepper("", value: $alarmTemperature, in: 55...110)
                            .labelsHidden()
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.accent)
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        let fmt = Self.timeFormatter
        let updated = AlarmSchedule(
            vibrationIntensity: Int(vibrationIntensity),
            vibrationPattern: vibrationPattern,
            duration: Int(duration),
            time: fmt.string(from: alarmTime),
            enabled: true,
            alarmTemperature: alarmTemperature
        )
        isSaving = true
        Task {
            await scheduleManager.updateAlarmSchedule(updated)
            Haptics.success()
            dismiss()
        }
    }
}

// MARK: - Schedule Side Selector

private struct ScheduleSideSelectorView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager

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
        case .left: settingsManager.leftName
        case .right: settingsManager.rightName
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
