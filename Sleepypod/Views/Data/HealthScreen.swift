import SwiftUI
import Charts

struct HealthScreen: View {
    @Environment(MetricsManager.self) private var metricsManager
    @Environment(SettingsManager.self) private var settingsManager

    // Real-time vitals
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
                // Week navigator
                WeekNavigatorView()

                // Side selector
                HealthSideSelectorView()

                if metricsManager.isLoading && metricsManager.sleepRecords.isEmpty {
                    LoadingView(message: "Loading health data…")
                } else {
                    // Calibration warning (only if not calibrated)
                    if !isCalibrated {
                        calibrationWarning
                    }

                    // Sleep summary
                    SleepSummaryCardView()

                    // On-device sleep analysis (ML)
                    if !sleepAnalyzer.stages.isEmpty {
                        sleepAnalysisCard
                    }

                    // Vitals summary
                    vitalsSummaryCard

                    // Heart rate chart (interactive)
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

                    // HRV chart
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

                    // Breathing rate
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

                    // Sleep stages timeline
                    SleepStagesTimelineView()

                    // Weekly bar chart
                    WeeklyBarChartView()

                    // Movement
                    MovementCardView()

                    // Raw data button → opens bottom sheet
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

    // MARK: - Smoothed Vitals

    /// Filter outliers and apply moving average
    private var smoothedVitals: [VitalsRecord] {
        vitals
            .filter { r in
                // Filter physiologically impossible values
                if let hr = r.heartRate, (hr < 30 || hr > 200) { return false }
                if let hrv = r.hrv, hrv > 300 { return false }
                return true
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Vitals Summary

    private var vitalsSummaryCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                let hrs = smoothedVitals.compactMap(\.heartRate)
                let hrvs = smoothedVitals.compactMap(\.hrv)
                let brs = smoothedVitals.compactMap(\.breathingRate)

                summaryItem(icon: "heart.fill", value: avg(hrs), unit: "BPM", color: Theme.error)
                Spacer()
                summaryItem(icon: "waveform.path.ecg", value: avg(hrvs), unit: "ms", color: Theme.accent)
                Spacer()
                summaryItem(icon: "lungs.fill", value: avg(brs), unit: "BR", color: Theme.healthy)
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
        .cardStyle()
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


    // MARK: - Sleep Analysis Card

    private var sleepAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundColor(Theme.purple)
                    Text("SLEEP ANALYSIS")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(1)
                }
                Spacer()
                if let score = sleepAnalyzer.qualityScore {
                    Text("Score: \(score)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(score >= 70 ? Theme.healthy : score >= 40 ? Theme.amber : Theme.error)
                }
            }

            Text("On-device · Rule-based")
                .font(.caption2)
                .foregroundColor(Theme.textMuted)

            // Stage distribution bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    let total = max(sleepAnalyzer.stages.count, 1)
                    let deep = sleepAnalyzer.stages.filter { $0.stage == .deep }.count
                    let light = sleepAnalyzer.stages.filter { $0.stage == .light }.count
                    let rem = sleepAnalyzer.stages.filter { $0.stage == .rem }.count
                    let wake = sleepAnalyzer.stages.filter { $0.stage == .wake }.count

                    stageBar(pct: Double(deep) / Double(total), color: Color(hex: "2563eb"), width: geo.size.width)
                    stageBar(pct: Double(light) / Double(total), color: Color(hex: "4a90d9"), width: geo.size.width)
                    stageBar(pct: Double(rem) / Double(total), color: Color(hex: "a080d0"), width: geo.size.width)
                    stageBar(pct: Double(wake) / Double(total), color: Color(hex: "888888"), width: geo.size.width)
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)

            // Legend
            HStack(spacing: 16) {
                stageLegend("Deep", color: Color(hex: "2563eb"), pct: stagePct(.deep))
                stageLegend("Light", color: Color(hex: "4a90d9"), pct: stagePct(.light))
                stageLegend("REM", color: Color(hex: "a080d0"), pct: stagePct(.rem))
                stageLegend("Wake", color: Color(hex: "888888"), pct: stagePct(.wake))
            }
        }
        .cardStyle()
    }

    private func stageBar(pct: Double, color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width * pct - 1, 0))
    }

    private func stageLegend(_ label: String, color: Color, pct: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(pct)%")
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func stagePct(_ stage: SleepAnalyzer.SleepStage) -> Int {
        guard !sleepAnalyzer.stages.isEmpty else { return 0 }
        return Int(Double(sleepAnalyzer.stages.filter { $0.stage == stage }.count) / Double(sleepAnalyzer.stages.count) * 100)
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
        guard let left = try? await api.getCalibrationStatus(side: .left),
              let right = try? await api.getCalibrationStatus(side: .right) else { return }
        // Consider calibrated if piezo sensors on both sides completed
        isCalibrated = left.piezo.status == "completed" && right.piezo.status == "completed"
            && (left.piezo.qualityScore ?? 0) > 0.5 && (right.piezo.qualityScore ?? 0) > 0.5
    }

    private func fetchVitals() async {
        isLoadingVitals = vitals.isEmpty
        let end = metricsManager.selectedWeekEnd
        let start = metricsManager.selectedWeekStart
        do {
            vitals = try await api.getVitals(side: metricsManager.selectedSide, start: start, end: end)
        } catch {
            Log.network.error("Failed to fetch vitals: \(error)")
        }
        isLoadingVitals = false
        sleepAnalyzer.analyze(vitals: vitals)
    }
}

// MARK: - Side Selector

private struct HealthSideSelectorView: View {
    @Environment(MetricsManager.self) private var metricsManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Side.allCases) { side in
                let isSelected = metricsManager.selectedSide == side
                Button {
                    Haptics.tap()
                    metricsManager.selectedSide = side
                } label: {
                    Text(side.displayName)
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
