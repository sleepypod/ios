import SwiftUI
import Charts
import HealthKit

struct SmartCurveView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var bedtime = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @State private var wakeTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var intensity: CoolingIntensity = .balanced
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var healthSynced = false
    @State private var healthError: String?

    private var curve: [SleepCurve.Point] {
        SleepCurve.generate(bedtime: bedtime, wakeTime: wakeTime, coolingIntensity: intensity)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Time pickers
            HStack(spacing: 12) {
                timePicker("Bedtime", icon: "moon.fill", color: Theme.purple, date: $bedtime)
                timePicker("Wake", icon: "sun.max.fill", color: Theme.amber, date: $wakeTime)
            }

            // Intensity picker
            HStack(spacing: 0) {
                ForEach(CoolingIntensity.allCases) { level in
                    let isSelected = intensity == level
                    Button {
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) { intensity = level }
                    } label: {
                        Text(level.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundColor(isSelected ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? Theme.cooling : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 11))

            // Health sync + intensity description
            HStack {
                Text(intensity.description)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)

                Spacer()

                Button {
                    Haptics.light()
                    importFromHealth()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: healthSynced ? "checkmark.circle.fill" : "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(healthSynced ? Theme.healthy : .red)
                        Text(healthSynced ? "Synced" : "Sync from Apple Health")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(healthSynced ? Theme.healthy : Theme.accent)
                    }
                }
                .buttonStyle(.plain)
            }

            if let err = healthError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(Theme.error)
            }

            // Curve chart
            curveChart
                .frame(height: 200)

            // Phase legend
            phaseLegend

            // Apply button
            Button {
                Haptics.medium()
                applyToSchedule()
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else if showSuccess {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "calendar.badge.plus")
                    }
                    Text(showSuccess ? "Applied!" : isSaving ? "Saving…" : "Apply to Schedule")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(showSuccess ? Theme.healthy : Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .cardStyle()
    }

    // MARK: - Chart

    private var curveChart: some View {
        Chart {
            // Phase background colors
            ForEach(phaseRanges, id: \.phase) { range in
                RectangleMark(
                    xStart: .value("Start", range.start),
                    xEnd: .value("End", range.end),
                    yStart: .value("Min", -10),
                    yEnd: .value("Max", 10)
                )
                .foregroundStyle(range.color.opacity(0.06))
            }

            // Zero line (base temp)
            RuleMark(y: .value("Base", 0))
                .foregroundStyle(Theme.textMuted.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Curve line
            ForEach(curve) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Offset", point.tempOffset)
                )
                .foregroundStyle(
                    TempColor.colorForDelta(point.tempOffset)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))

                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Offset", point.tempOffset)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [TempColor.colorForDelta(point.tempOffset).opacity(0.2), Color.clear],
                        startPoint: point.tempOffset > 0 ? .top : .bottom,
                        endPoint: point.tempOffset > 0 ? .bottom : .top
                    )
                )
                .interpolationMethod(.catmullRom)
            }

        }
        .chartYScale(domain: -10...10)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-8, -4, 0, 4, 8]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    .foregroundStyle(Theme.cardBorder)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        let format = settingsManager.temperatureFormat
                        if format == .relative {
                            Text(v > 0 ? "+\(v)" : "\(v)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                        } else {
                            Text(TemperatureConversion.displayTemp(80 + v, format: format))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    // MARK: - Phase Ranges

    private struct PhaseRange {
        let phase: String
        let start: Date
        let end: Date
        let color: Color
    }

    private var phaseRanges: [PhaseRange] {
        let grouped = Dictionary(grouping: curve, by: \.phase)
        return grouped.compactMap { phase, points in
            guard let first = points.min(by: { $0.time < $1.time }),
                  let last = points.max(by: { $0.time < $1.time }) else { return nil }
            return PhaseRange(
                phase: phase.rawValue,
                start: first.time,
                end: last.time,
                color: phaseColor(phase)
            )
        }
    }

    private func phaseColor(_ phase: SleepCurve.Phase) -> Color {
        switch phase {
        case .warmUp: Theme.warming
        case .coolDown: Theme.cooling
        case .deepSleep: Color(hex: "2563eb")
        case .maintain: Theme.cooling
        case .preWake: Theme.amber
        case .wake: Theme.textMuted
        }
    }

    // MARK: - Legend

    private var phaseLegend: some View {
        let phases: [(String, Color, String)] = [
            ("Wind Down", Theme.warming, "+warm"),
            ("Fall Asleep", Theme.cooling, "cool"),
            ("Deep Sleep", Color(hex: "2563eb"), "coldest"),
            ("Pre-Wake", Theme.amber, "+warm"),
        ]
        return HStack(spacing: 12) {
            ForEach(phases, id: \.0) { name, color, label in
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(name)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Time Picker

    private func timePicker(_ label: String, icon: String, color: Color, date: Binding<Date>) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(Theme.textSecondary)
            }
            DatePicker("", selection: date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - HealthKit Import

    private func importFromHealth() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthError = "Health data not available on this device"
            return
        }

        let store = HKHealthStore()
        let sleepType = HKCategoryType(.sleepAnalysis)

        store.requestAuthorization(toShare: nil, read: [sleepType]) { success, error in
            guard success else {
                DispatchQueue.main.async {
                    healthError = "Health access denied — enable in Settings → Privacy → Health"
                }
                return
            }

            // Query the most recent sleep schedule / sleep analysis to find bed + wake pattern
            let calendar = Calendar.current
            let now = Date()
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!

            let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: now)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 20,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, queryError in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    DispatchQueue.main.async {
                        healthError = "No recent sleep data found in Health"
                    }
                    return
                }

                // Find the most recent "in bed" period
                // inBed = 0, asleep/asleepUnspecified = 1, awake = 2, asleepCore = 3, asleepDeep = 4, asleepREM = 5
                let inBedSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                let sleepSamples = samples.filter {
                    [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                     HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains($0.value)
                }

                let recentSession = inBedSamples.first ?? sleepSamples.first
                guard let session = recentSession else {
                    DispatchQueue.main.async {
                        healthError = "No sleep sessions found"
                    }
                    return
                }

                // Extract bed and wake times (just the hour:minute, applied to today)
                let bedComponents = calendar.dateComponents([.hour, .minute], from: session.startDate)
                let wakeComponents = calendar.dateComponents([.hour, .minute], from: session.endDate)

                DispatchQueue.main.async {
                    if let bedHour = bedComponents.hour, let bedMin = bedComponents.minute {
                        var c = calendar.dateComponents([.year, .month, .day], from: now)
                        c.hour = bedHour
                        c.minute = bedMin
                        bedtime = calendar.date(from: c) ?? bedtime
                    }
                    if let wakeHour = wakeComponents.hour, let wakeMin = wakeComponents.minute {
                        var c = calendar.dateComponents([.year, .month, .day], from: now)
                        c.hour = wakeHour
                        c.minute = wakeMin
                        wakeTime = calendar.date(from: c) ?? wakeTime
                    }
                    healthSynced = true
                    healthError = nil
                    Haptics.medium()
                }
            }

            store.execute(query)
        }
    }

    // MARK: - Apply

    private func applyToSchedule() {
        isSaving = true
        let temps = SleepCurve.toScheduleTemperatures(curve)

        Task {
            guard var schedules = scheduleManager.schedules else {
                isSaving = false
                return
            }

            let side = scheduleManager.selectedSide.primarySide
            var sideSchedule = schedules.schedule(for: side)
            var daily = sideSchedule[scheduleManager.selectedDay]

            // Replace temperatures
            daily.temperatures = temps

            // Update power schedule
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            daily.power.on = fmt.string(from: bedtime)
            daily.power.off = fmt.string(from: wakeTime)
            daily.power.enabled = true

            // Update alarm
            daily.alarm.time = fmt.string(from: wakeTime)
            daily.alarm.enabled = true

            sideSchedule[scheduleManager.selectedDay] = daily
            schedules.setSchedule(sideSchedule, for: side)

            // Apply to both sides if linked
            if scheduleManager.selectedSide == .both {
                var other = schedules.schedule(for: side == .left ? .right : .left)
                other[scheduleManager.selectedDay] = daily
                schedules.setSchedule(other, for: side == .left ? .right : .left)
            }

            scheduleManager.schedules = schedules
            do {
                let api = APIBackend.current.createClient()
                scheduleManager.schedules = try await api.updateSchedules(schedules)
            } catch {
                Log.general.error("Failed to save smart curve: \(error)")
            }

            isSaving = false
            withAnimation { showSuccess = true }
            Haptics.heavy()
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSuccess = false }
        }
    }
}

// MARK: - TempColor helper

private extension TempColor {
    static func colorForDelta(_ delta: Int) -> Color {
        if delta <= -6 { return Color(hex: "2563eb") }
        if delta <= -2 { return Theme.cooling }
        if delta >= 4 { return Theme.warming }
        if delta >= 1 { return Color(hex: "e0976a") }
        return Theme.textSecondary
    }
}
