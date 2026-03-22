import SwiftUI
import Charts

struct HealthScreen: View {
    @Environment(MetricsManager.self) private var metricsManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var vitals: [VitalsRecord] = []
    @State private var isLoadingVitals = false
    @State private var showRawData = false
    @State private var sleepAnalyzer = SleepAnalyzer()
    @State private var isCalibrated = false
    @State private var showCalibrationSheet = false

    private var api: SleepypodProtocol { APIBackend.current.createClient() }

    private var selectedSide: Side { metricsManager.selectedSide }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    WeekNavigatorView()
                    Spacer()
                    sideTogglePill
                }

                if metricsManager.isLoading && metricsManager.sleepRecords.isEmpty {
                    LoadingView(message: "Loading health data…")
                } else {
                    // Calibration warning (non-blocking, scrollable)
                    if !isCalibrated {
                        calibrationWarning
                    }

                    // Sleep
                    SleepSummaryCardView()
                    SleepStagesTimelineView(stages: sleepAnalyzer.stages, qualityScore: sleepAnalyzer.qualityScore)

                    // Vitals
                    vitalsSummaryCard

                    VitalsChartCard(
                        title: "Heart Rate",
                        icon: "heart.fill",
                        color: Theme.error,
                        unit: "BPM",
                        records: smoothedVitals,
                        valueKey: \.heartRate,
                        zones: [
                            Zone(label: "Resting", range: 40...60, color: Theme.cooling.opacity(0.08)),
                            Zone(label: "Normal", range: 60...100, color: Theme.healthy.opacity(0.05)),
                            Zone(label: "Elevated", range: 100...140, color: Theme.amber.opacity(0.05))
                        ],
                        average: metricsManager.vitalsSummary?.avgHeartRate
                    )

                    VitalsChartCard(
                        title: "Heart Rate Variability",
                        icon: "waveform.path.ecg",
                        color: Theme.accent,
                        unit: "ms",
                        records: smoothedVitals,
                        valueKey: \.hrv,
                        zones: [
                            Zone(label: "Low", range: 0...30, color: Theme.amber.opacity(0.08)),
                            Zone(label: "Normal", range: 30...100, color: Theme.healthy.opacity(0.05)),
                            Zone(label: "High", range: 100...200, color: Theme.accent.opacity(0.05))
                        ],
                        average: metricsManager.vitalsSummary?.avgHRV
                    )

                    VitalsChartCard(
                        title: "Breathing Rate",
                        icon: "lungs.fill",
                        color: Theme.healthy,
                        unit: "BPM",
                        records: smoothedVitals,
                        valueKey: \.breathingRate,
                        zones: [
                            Zone(label: "Normal", range: 12...20, color: Theme.healthy.opacity(0.08))
                        ],
                        average: metricsManager.vitalsSummary?.avgBreathingRate
                    )

                    // Trends
                    WeeklyBarChartView()
                    MovementCardView()

                    // Raw data
                    Button {
                        Haptics.light()
                        showRawData = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.textSecondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Raw Data")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                Text("\(vitals.count) vitals · \(metricsManager.sleepRecords.count) sleep · \(metricsManager.selectedSide.displayName) side")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.accent)
                        }
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .refreshable { await refresh() }
        .task { await refresh() }
        .sheet(isPresented: $showRawData) {
            RawDataSheet(
                vitals: vitals,
                smoothedVitals: smoothedVitals,
                metricsManager: metricsManager
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: metricsManager.selectedSide) {
            Task { await refresh() }
        }
        .sheet(isPresented: $showCalibrationSheet) {
            CalibrationSheet(onComplete: {
                Task { await checkCalibration() }
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Side Toggle

    private var sideName: String {
        settingsManager.sideName(for: metricsManager.selectedSide)
    }

    private var sideBadge: String {
        metricsManager.selectedSide == .left ? "L" : "R"
    }

    private var sideTogglePill: some View {
        Button {
            Haptics.light()
            withAnimation(.easeInOut(duration: 0.2)) {
                metricsManager.selectedSide = metricsManager.selectedSide == .left ? .right : .left
            }
        } label: {
            HStack(spacing: 5) {
                Text(sideName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)

                Text(sideBadge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Theme.accent.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Smoothed Vitals

    /// Filter outliers and apply moving average.
    /// Uses tighter sleep-context thresholds matching SleepAnalyzer.
    private var smoothedVitals: [VitalsRecord] {
        vitals
            .filter { r in
                // Filter physiologically impossible values (sleep-context thresholds)
                if let hr = r.heartRate, (hr < 45 || hr > 130) { return false }
                if let hrv = r.hrv, hrv > 300 { return false }
                if let br = r.breathingRate, (br < 8 || br > 25) { return false }
                return true
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Vitals Summary

    private var vitalsSummaryCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                let hrs = smoothedVitals.compactMap(\.heartRate)
                let hrvs = smoothedVitals.compactMap(\.hrv)
                let brs = smoothedVitals.compactMap(\.breathingRate)

                vitalCard(icon: "heart.fill", label: "Heart Rate", value: avg(hrs), unit: "bpm",
                          min: hrs.isEmpty ? nil : "\(Int(hrs.min()!))", max: hrs.isEmpty ? nil : "\(Int(hrs.max()!))",
                          color: Theme.error)
                vitalCard(icon: "waveform.path.ecg", label: "HRV", value: avg(hrvs), unit: "ms",
                          min: hrvs.isEmpty ? nil : "\(Int(hrvs.min()!))", max: hrvs.isEmpty ? nil : "\(Int(hrvs.max()!))",
                          color: Theme.accent)
                vitalCard(icon: "lungs.fill", label: "Breathing", value: avg(brs), unit: "brpm",
                          min: brs.isEmpty ? nil : "\(Int(brs.min()!))", max: brs.isEmpty ? nil : "\(Int(brs.max()!))",
                          color: Theme.healthy)
            }

            // Trend analysis
            if let trend = trendText {
                HStack(spacing: 6) {
                    Image(systemName: trend.icon)
                        .font(.system(size: 10))
                    Text(trend.text)
                        .font(.caption2)
                }
                .foregroundColor(trend.color)
            }
        }
    }

    private func vitalCard(icon: String, label: String, value: String, unit: String,
                           min: String?, max: String?, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(unit)
                .font(.system(size: 9))
                .foregroundColor(Theme.textMuted)

            if let min, let max {
                HStack(spacing: 2) {
                    Text(min)
                        .foregroundColor(Theme.cooling)
                    Text("–")
                        .foregroundColor(Theme.textMuted)
                    Text(max)
                        .foregroundColor(Theme.warming)
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }

    private var trendText: (text: String, icon: String, color: Color)? {
        let values = smoothedVitals.compactMap(\.hrv)
        guard values.count >= 10 else { return nil }

        let mid = values.count / 2
        let recent = Array(values[mid...])
        let older = Array(values[..<mid])
        guard !recent.isEmpty, !older.isEmpty else { return nil }

        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        guard olderAvg > 0 else { return nil }

        let delta = ((recentAvg - olderAvg) / olderAvg) * 100

        if delta > 10 {
            return ("HRV improving +\(Int(delta))%", "arrow.up.right", Theme.healthy)
        } else if delta < -10 {
            return ("HRV declining \(Int(delta))%", "arrow.down.right", Theme.amber)
        }
        return ("HRV stable", "equal", Theme.textSecondary)
    }

    private func avg(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "--" }
        return "\(Int(values.reduce(0, +) / Double(values.count)))"
    }

    private func summaryItem(icon: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text(unit)
                .font(.caption2)
                .foregroundColor(Theme.textMuted)
        }
    }


    // MARK: - Calibration Warning

    private var calibrationWarning: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data may be uncalibrated")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Theme.amber)
                    Text("Piezo sensors require calibration for accurate readings. Values shown may not reflect actual vitals.")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
            }

            Button {
                Haptics.medium()
                showCalibrationSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tuningfork")
                    Text("Recalibrate Sensors")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.amber)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.amber.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    // MARK: - Fetch

    private func refresh() async {
        await metricsManager.fetchAll()
        await fetchVitals()
        await checkCalibration()
    }

    private func checkCalibration() async {
        let api = APIBackend.current.createClient()
        guard let status = try? await api.getCalibrationStatus(side: metricsManager.selectedSide) else { return }
        // Only warn if selected side's piezo is missing or low quality
        isCalibrated = status.piezo?.status == "completed" && (status.piezo?.qualityScore ?? 0) > 0.5
    }

    private func fetchVitals() async {
        isLoadingVitals = vitals.isEmpty
        let end = metricsManager.selectedWeekEnd
        let start = metricsManager.selectedWeekStart
        Log.general.info("Fetching vitals: side=\(metricsManager.selectedSide.rawValue) start=\(start) end=\(end)")
        do {
            vitals = try await api.getVitals(side: metricsManager.selectedSide, start: start, end: end)
            Log.general.info("Fetched \(vitals.count) vitals records")
        } catch {
            Log.network.error("Failed to fetch vitals: \(error)")
        }
        isLoadingVitals = false

        // Fetch calibration quality for sleep analysis
        let calibrationQuality: Double
        if let status = try? await api.getCalibrationStatus(side: metricsManager.selectedSide) {
            calibrationQuality = status.piezo?.qualityScore ?? 0.0
        } else {
            calibrationQuality = 0.0  // Unknown quality — fail closed, don't trust unverified vitals
        }

        sleepAnalyzer.analyze(
            vitals: vitals,
            movement: metricsManager.movementRecords,
            calibrationQuality: calibrationQuality
        )
        Log.general.info("Sleep analyzer: \(sleepAnalyzer.stages.count) stages, score=\(sleepAnalyzer.qualityScore ?? -1)")
    }
}


// MARK: - Zone

struct Zone {
    let label: String
    let range: ClosedRange<Double>
    let color: Color
}

// MARK: - Vitals Chart Card

struct VitalsChartCard: View {
    let title: String
    let icon: String
    let color: Color
    let unit: String
    let records: [VitalsRecord]
    let valueKey: KeyPath<VitalsRecord, Double?>
    let zones: [Zone]
    let average: Double?

    @State private var selectedDate: Date?

    private var dataPoints: [(Date, Double)] {
        records.compactMap { r in
            r[keyPath: valueKey].map { (r.date, $0) }
        }
    }

    private var selectedRecord: VitalsRecord? {
        guard let date = selectedDate else { return nil }
        return records.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    private var values: [Double] { dataPoints.map(\.1) }
    private var minVal: Double { values.min() ?? 0 }
    private var maxVal: Double { values.max() ?? 0 }
    private var avgVal: Double {
        average ?? (values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(color)
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(1)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    let displayVal = selectedRecord?[keyPath: valueKey] ?? dataPoints.last?.1
                    let displayTime = selectedRecord?.timeLabel

                    Text("\(Int(displayVal ?? 0)) \(unit)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(color)
                    Text(displayTime ?? " ")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
                .frame(width: 70, alignment: .trailing)
            }

            if dataPoints.isEmpty {
                Text("No data available")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    // Zone backgrounds
                    ForEach(zones, id: \.label) { zone in
                        RectangleMark(
                            yStart: .value("Min", zone.range.lowerBound),
                            yEnd: .value("Max", zone.range.upperBound)
                        )
                        .foregroundStyle(zone.color)
                    }

                    // Average line
                    RuleMark(y: .value("Avg", avgVal))
                        .foregroundStyle(color.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .leading) {
                            Text("avg")
                                .font(.system(size: 8))
                                .foregroundColor(color.opacity(0.5))
                        }

                    // Data line — use record ID for stable identity
                    ForEach(records.filter { $0[keyPath: valueKey] != nil }, id: \.id) { record in
                        if let val = record[keyPath: valueKey] {
                            LineMark(
                                x: .value("Time", record.date),
                                y: .value(title, val)
                            )
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            AreaMark(
                                x: .value("Time", record.date),
                                y: .value(title, val)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [color.opacity(0.2), color.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                        }
                    }

                    // Selection indicator
                    if let sel = selectedRecord, let val = sel[keyPath: valueKey] {
                        PointMark(
                            x: .value("Time", sel.date),
                            y: .value(title, val)
                        )
                        .foregroundStyle(.white)
                        .symbolSize(60)

                        RuleMark(x: .value("Time", sel.date))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Theme.cardBorder)
                        AxisValueLabel()
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let date: Date = proxy.value(atX: location.x) else { return }
                                Haptics.light()
                                if selectedDate != nil && abs((selectedDate ?? .distantPast).timeIntervalSince(date)) < 60 {
                                    selectedDate = nil
                                } else {
                                    selectedDate = date
                                }
                            }
                    }
                }
                .frame(height: 180)

                // Legend: min / avg / max + zone labels
                HStack(spacing: 16) {
                    legendItem("Min", value: "\(Int(minVal))", color: Theme.textMuted)
                    legendItem("Avg", value: "\(Int(avgVal))", color: color.opacity(0.7))
                    legendItem("Max", value: "\(Int(maxVal))", color: Theme.textMuted)

                    Spacer()

                    // Zone labels
                    ForEach(zones, id: \.label) { zone in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(zone.color.opacity(3))
                                .frame(width: 8, height: 8)
                            Text(zone.label)
                                .font(.system(size: 9))
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private func legendItem(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption2.weight(.medium).monospaced())
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Theme.textMuted)
        }
    }
}
