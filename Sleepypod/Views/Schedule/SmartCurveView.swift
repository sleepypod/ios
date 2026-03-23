import SwiftUI
import Charts
import HealthKit

struct SmartCurveView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager
    @Binding var showCurvePicker: Bool

    @State private var bedtime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 22; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var wakeTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.day = (c.day ?? 0) + 1
        c.hour = 7; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var intensity: CoolingIntensity = .balanced
    @State private var selectedProfile: SmartProfile = .balanced
    @State private var isSaving = false
    @State private var isRunOnce = false
    @State private var showSuccess = false
    @State private var healthSynced = false
    @State private var healthError: String?
    @State private var minTemp: Double = 68
    @State private var maxTemp: Double = 86
    @State private var customCurvePoints: [SleepCurve.Point]?

    /// Whether the chart is showing custom schedule temperatures rather than a generated curve
    private var isShowingCustomCurve: Bool { customCurvePoints != nil }

    /// Y-axis adapts to include curve range AND min/max lines with padding
    private var yDomain: ClosedRange<Int> {
        let curveOffsets = curve.map(\.tempOffset)
        let minLine = Int(minTemp) - 80
        let maxLine = Int(maxTemp) - 80
        let allValues = curveOffsets + [minLine, maxLine, 0]
        let lo = (allValues.min() ?? -10) - 2
        let hi = (allValues.max() ?? 10) + 2
        return lo...hi
    }

    private var curve: [SleepCurve.Point] {
        if let customCurvePoints {
            return customCurvePoints
        }
        return SleepCurve.generate(
            bedtime: bedtime,
            wakeTime: wakeTime,
            coolingIntensity: intensity,
            minTempF: Int(minTemp),
            maxTempF: Int(maxTemp)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            // Time pickers
            HStack(spacing: 12) {
                timePicker("Bedtime", icon: "moon.fill", color: Theme.purple, date: $bedtime)
                timePicker("Wake", icon: "sun.max.fill", color: Theme.amber, date: $wakeTime)
            }

            // Profile picker — centered
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ForEach(SmartProfile.allProfiles) { profile in
                        let isSelected = selectedProfile.id == profile.id
                        Button {
                            Haptics.tap()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                customCurvePoints = nil
                                selectedProfile = profile
                                intensity = profile.intensity
                                minTemp = Double(profile.minTempF)
                                maxTemp = Double(profile.maxTempF)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: profile.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(isSelected ? .white : Theme.textSecondary)
                                Text(profile.name)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(isSelected ? .white : Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 72, height: 52)
                            .background(isSelected ? Theme.accent.opacity(0.3) : Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Custom curves button
                    Button {
                        Haptics.tap()
                        showCurvePicker = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.accent)
                            Text("Custom")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(Theme.accent)
                                .lineLimit(1)
                        }
                        .frame(width: 72, height: 52)
                        .background(Theme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            Text(selectedProfile.description)
                .font(.caption2)
                .foregroundColor(Theme.textMuted)

            // Curve chart with draggable min/max
            curveChart
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotArea = geo[proxy.plotFrame!]

                        // Full chart drag — top half = max, bottom half = min
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: plotArea.width, height: plotArea.height)
                            .offset(x: plotArea.minX, y: plotArea.minY)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        let localY = value.location.y - plotArea.minY
                                        guard let offset = proxy.value(atY: localY) as Int? else { return }

                                        let midY = plotArea.height / 2
                                        if value.startLocation.y - plotArea.minY > midY {
                                            // Started in bottom half — adjust min
                                            let temp = max(55, min(Double(Int(maxTemp) - 2), Double(80 + offset)))
                                            minTemp = temp.rounded()
                                        } else {
                                            // Started in top half — adjust max
                                            let temp = min(110, max(Double(Int(minTemp) + 2), Double(80 + offset)))
                                            maxTemp = temp.rounded()
                                        }
                                    }
                            )
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Phase legend
            phaseLegend

            // Min / Max temp controls
            HStack(spacing: 24) {
                tempStepper(
                    label: "Coolest",
                    icon: "snowflake",
                    color: Theme.cooling,
                    value: $minTemp,
                    range: 55...Double(Int(maxTemp) - 2)
                )

                // Divider
                Rectangle()
                    .fill(Theme.cardBorder)
                    .frame(width: 1, height: 36)

                tempStepper(
                    label: "Warmest",
                    icon: "flame.fill",
                    color: Theme.warming,
                    value: $maxTemp,
                    range: Double(Int(minTemp) + 2)...110
                )
            }
            .frame(maxWidth: .infinity)


            // Split button: Apply to Schedule | Use Now
            HStack(spacing: 0) {
                Button {
                    Haptics.medium()
                    applyToSchedule()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving && !isRunOnce {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else if showSuccess && !isRunOnce {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: "calendar.badge.plus")
                        }
                        Text(showSuccess && !isRunOnce ? "Applied!" : isSaving && !isRunOnce ? "Saving…" : "Apply to Schedule")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .disabled(isSaving)

                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.3))

                Button {
                    Haptics.medium()
                    useNow()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving && isRunOnce {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else if showSuccess && isRunOnce {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(showSuccess && isRunOnce ? "Started!" : isSaving && isRunOnce ? "Starting…" : "Use Now")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .disabled(isSaving)
            }
            .background(showSuccess ? Theme.healthy : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .buttonStyle(.plain)
        }
        .onAppear { loadFromSchedule() }
        .onChange(of: scheduleManager.selectedDay) { loadFromSchedule() }
        .onChange(of: scheduleManager.schedules != nil) { loadFromSchedule() }
        .onChange(of: scheduleManager.currentDailySchedule?.temperatures) { loadFromSchedule() }
        .cardStyle()
    }


    private func tempStepper(label: String, icon: String, color: Color, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.textMuted)

            HStack(spacing: 12) {
                Button {
                    Haptics.light()
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.cardElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(color)
                    Text(TemperatureConversion.displayTemp(Int(value.wrappedValue), format: settingsManager.temperatureFormat))
                        .font(.subheadline.weight(.semibold).monospaced())
                        .foregroundColor(.white)
                }
                .frame(minWidth: 60)

                Button {
                    Haptics.light()
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.cardElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Phase Transitions

    private var phaseTransitions: [(label: String, time: Date, color: Color)] {
        var transitions: [(String, Date, Color)] = []
        var lastPhase: SleepCurve.Phase?
        for point in curve {
            if point.phase != lastPhase {
                let color: Color = switch point.phase {
                case .warmUp: Theme.warming
                case .coolDown: Theme.cooling
                case .deepSleep: Color(hex: "2563eb")
                case .maintain: Theme.cooling
                case .preWake: Theme.amber
                case .wake: Theme.textMuted
                }
                transitions.append((point.phase.rawValue, point.time, color))
                lastPhase = point.phase
            }
        }
        return transitions
    }

    // MARK: - Chart

    private var curveChart: some View {
        Chart {
            // Zero line (base temp)
            RuleMark(y: .value("Base", 0))
                .foregroundStyle(Theme.textMuted.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Min temp line
            RuleMark(y: .value("Min", Int(minTemp) - 80))
                .foregroundStyle(Theme.cooling.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1))

            // Max temp line
            RuleMark(y: .value("Max", Int(maxTemp) - 80))
                .foregroundStyle(Theme.warming.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1))

            // Phase background fills
            ForEach(Array(phaseTransitions.enumerated()), id: \.offset) { i, t in
                let nextTime = i + 1 < phaseTransitions.count ? phaseTransitions[i + 1].time : curve.last?.time ?? t.time
                RectangleMark(
                    xStart: .value("Start", t.time),
                    xEnd: .value("End", nextTime),
                    yStart: .value("Min", yDomain.lowerBound),
                    yEnd: .value("Max", yDomain.upperBound)
                )
                .foregroundStyle(t.color.opacity(0.12))
            }

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
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
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
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour())
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                            .rotationEffect(.degrees(-45))
                            .fixedSize()
                    }
                }
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
        let phases: [(name: String, color: Color)] = [
            ("Wind Down", Theme.warming),
            ("Fall Asleep", Theme.cooling),
            ("Deep Sleep", Color(hex: "2563eb")),
            ("Pre-Wake", Theme.amber),
        ]
        return HStack(spacing: 12) {
            ForEach(phases, id: \.name) { phase in
                HStack(spacing: 4) {
                    Circle().fill(phase.color).frame(width: 6, height: 6)
                    Text(phase.name)
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
        let sleepAnalysis = HKCategoryType(.sleepAnalysis)
        let typesToRead: Set<HKSampleType> = [sleepAnalysis]

        store.requestAuthorization(toShare: nil, read: typesToRead) { success, _ in
            guard success else {
                Task { @MainActor in healthError = "Health access denied" }
                return
            }

            Task {
                // The iOS Sleep Schedule (set in Clock/Health) writes
                // future-dated "inBed" samples that represent the schedule.
                // Query for samples starting from now into the future.
                let calendar = Calendar.current
                let now = Date()
                let tomorrow = calendar.date(byAdding: .day, value: 2, to: now)!

                // Try future schedule first (the sleep schedule creates forward-looking samples)
                if let times = await queryScheduleSamples(store: store, start: now, end: tomorrow) {
                    await MainActor.run { applyTimes(bed: times.bed, wake: times.wake) }
                    return
                }

                // Fallback: recent past sleep data
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
                if let times = await queryScheduleSamples(store: store, start: weekAgo, end: now) {
                    await MainActor.run { applyTimes(bed: times.bed, wake: times.wake) }
                    return
                }

                await MainActor.run {
                    healthError = "No sleep schedule or recent sleep data found"
                }
            }
        }
    }

    private func queryScheduleSamples(store: HKHealthStore, start: Date, end: Date) async -> (bed: Date, wake: Date)? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 50,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Look for inBed samples — the sleep schedule creates these
                let inBed = samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                // Also check asleep samples
                let asleep = samples.filter {
                    [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                     HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains($0.value)
                }

                if let session = inBed.first ?? asleep.first {
                    continuation.resume(returning: (bed: session.startDate, wake: session.endDate))
                } else {
                    continuation.resume(returning: nil)
                }
            }

            store.execute(query)
        }
    }

    @MainActor
    private func applyTimes(bed: Date, wake: Date) {
        let calendar = Calendar.current
        let now = Date()

        let bedC = calendar.dateComponents([.hour, .minute], from: bed)
        let wakeC = calendar.dateComponents([.hour, .minute], from: wake)

        if let h = bedC.hour, let m = bedC.minute {
            var c = calendar.dateComponents([.year, .month, .day], from: now)
            c.hour = h; c.minute = m
            bedtime = calendar.date(from: c) ?? bedtime
        }
        if let h = wakeC.hour, let m = wakeC.minute {
            var c = calendar.dateComponents([.year, .month, .day], from: now)
            c.hour = h; c.minute = m
            wakeTime = calendar.date(from: c) ?? wakeTime
        }

        healthSynced = true
        healthError = nil
        Haptics.medium()
    }

    // MARK: - Apply

    private func loadFromSchedule() {
        let calendar = Calendar.current
        let now = Date()

        // Reset to defaults first
        customCurvePoints = nil

        var bed = calendar.dateComponents([.year, .month, .day], from: now)
        bed.hour = 22; bed.minute = 0
        bedtime = calendar.date(from: bed) ?? bedtime

        var wake = calendar.dateComponents([.year, .month, .day], from: now)
        wake.day = (wake.day ?? 0) + 1
        wake.hour = 7; wake.minute = 0
        wakeTime = calendar.date(from: wake) ?? wakeTime

        minTemp = 68
        maxTemp = 86

        guard let daily = scheduleManager.currentDailySchedule else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"

        // Load bedtime from power schedule
        if daily.power.enabled, let date = fmt.date(from: daily.power.on) {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            var today = calendar.dateComponents([.year, .month, .day], from: now)
            today.hour = c.hour; today.minute = c.minute
            if let d = calendar.date(from: today) { bedtime = d }
        }

        // Load wake from alarm
        if daily.alarm.enabled, let date = fmt.date(from: daily.alarm.time) {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            var tomorrow = calendar.dateComponents([.year, .month, .day], from: now)
            tomorrow.day = (tomorrow.day ?? 0) + 1
            tomorrow.hour = c.hour; tomorrow.minute = c.minute
            if let d = calendar.date(from: tomorrow) { wakeTime = d }
        }

        // Infer min/max from existing temperature set points
        let temps = daily.temperatures.values
        if !temps.isEmpty {
            minTemp = Double(temps.min() ?? 68)
            maxTemp = Double(temps.max() ?? 86)
        }

        // Check if the schedule has custom temperatures that don't match
        // any built-in profile curve — if so, display the actual schedule points
        if daily.temperatures.count >= 3 {
            let matchesAnyProfile = SmartProfile.allProfiles.contains { profile in
                let profileTemps = SleepCurve.toScheduleTemperatures(
                    SleepCurve.generate(
                        bedtime: bedtime,
                        wakeTime: wakeTime,
                        coolingIntensity: profile.intensity,
                        minTempF: profile.minTempF,
                        maxTempF: profile.maxTempF
                    )
                )
                return daily.temperatures == profileTemps
            }
            // Also check the current profile selection with current min/max
            let currentProfileTemps = SleepCurve.toScheduleTemperatures(
                SleepCurve.generate(
                    bedtime: bedtime,
                    wakeTime: wakeTime,
                    coolingIntensity: intensity,
                    minTempF: Int(minTemp),
                    maxTempF: Int(maxTemp)
                )
            )
            let isCustom = !matchesAnyProfile && daily.temperatures != currentProfileTemps
            if isCustom {
                customCurvePoints = Self.buildCurvePoints(
                    from: daily.temperatures,
                    bedtime: bedtime,
                    wakeTime: wakeTime,
                    calendar: calendar,
                    now: now
                )
            }
        }
    }

    /// Build SleepCurve.Point values from schedule temperature set points
    /// so they can be displayed on the chart.
    private static func buildCurvePoints(
        from temperatures: [String: Int],
        bedtime: Date,
        wakeTime: Date,
        calendar: Calendar,
        now: Date
    ) -> [SleepCurve.Point] {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"

        let sorted = temperatures.sorted { $0.key < $1.key }
        let bedHour = calendar.component(.hour, from: bedtime)

        return sorted.compactMap { timeStr, tempF in
            guard let parsed = fmt.date(from: timeStr) else { return nil }
            let c = calendar.dateComponents([.hour, .minute], from: parsed)
            let pointHour = c.hour ?? 0
            // Evening times go on today; early-morning times (after midnight) on tomorrow
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
            if pointHour < 12 && bedHour >= 12 {
                dateComponents.day = (dateComponents.day ?? 0) + 1
            }
            dateComponents.hour = c.hour
            dateComponents.minute = c.minute
            guard let date = calendar.date(from: dateComponents) else { return nil }
            let offset = tempF - 80
            // Classify phase based on position relative to bedtime/wake
            let phase: SleepCurve.Phase
            if date < bedtime {
                phase = .warmUp
            } else if date >= wakeTime {
                phase = .wake
            } else {
                let total = wakeTime.timeIntervalSince(bedtime)
                let elapsed = date.timeIntervalSince(bedtime)
                let progress = elapsed / total
                if progress < 0.2 { phase = .coolDown }
                else if progress < 0.5 { phase = .deepSleep }
                else if progress < 0.8 { phase = .maintain }
                else { phase = .preWake }
            }
            return SleepCurve.Point(time: date, tempOffset: offset, phase: phase)
        }.sorted { $0.time < $1.time }
    }

    private func applyToSchedule() {
        isSaving = true
        let temps = SleepCurve.toScheduleTemperatures(curve)

        Task {
            guard var schedules = scheduleManager.schedules else {
                isSaving = false
                return
            }

            let side = scheduleManager.selectedSide.primarySide
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"

            // Apply to all selected days
            for day in scheduleManager.selectedDays {
                var sideSchedule = schedules.schedule(for: side)
                var daily = sideSchedule[day]

                daily.temperatures = temps
                daily.power.on = fmt.string(from: bedtime)
                daily.power.off = fmt.string(from: wakeTime)
                daily.power.enabled = true
                daily.alarm.time = fmt.string(from: wakeTime)
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

    private func useNow() {
        isSaving = true
        isRunOnce = true

        // Regenerate curve with bedtime = now
        let now = Date()
        let roundedNow = Calendar.current.date(
            bySetting: .minute,
            value: (Calendar.current.component(.minute, from: now) / 5) * 5,
            of: now
        ) ?? now

        let nowCurve = SleepCurve.generate(
            bedtime: roundedNow,
            wakeTime: wakeTime,
            coolingIntensity: intensity,
            minTempF: Int(minTemp),
            maxTempF: Int(maxTemp)
        )

        let temps = SleepCurve.toScheduleTemperatures(nowCurve)
        let side = scheduleManager.selectedSide.primarySide
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let wakeTimeStr = fmt.string(from: wakeTime)

        // Convert to set points array for the API
        let setPoints: [[String: Any]] = temps.sorted(by: { $0.key < $1.key }).map { time, temp in
            ["time": time, "temperature": temp]
        }

        Task {
            do {
                let api = APIBackend.current.createClient()
                let _ = try await api.startRunOnce(
                    side: side,
                    setPoints: setPoints,
                    wakeTime: wakeTimeStr
                )

                // If both sides, start the other side too
                if scheduleManager.selectedSide == .both {
                    let otherSide: Side = side == .left ? .right : .left
                    let _ = try await api.startRunOnce(
                        side: otherSide,
                        setPoints: setPoints,
                        wakeTime: wakeTimeStr
                    )
                }
            } catch {
                Log.general.error("Failed to start run-once: \(error)")
            }

            isSaving = false
            withAnimation { showSuccess = true }
            Haptics.heavy()
            try? await Task.sleep(for: .seconds(1))
            withAnimation { showSuccess = false }
            isRunOnce = false

            // Switch to Temp tab to show the active curve
            NotificationCenter.default.post(name: .switchToTempTab, object: nil)
        }
    }
}

extension Notification.Name {
    static let switchToTempTab = Notification.Name("switchToTempTab")
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
