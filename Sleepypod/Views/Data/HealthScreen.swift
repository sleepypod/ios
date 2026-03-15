import SwiftUI
import Charts

struct HealthScreen: View {
    @Environment(MetricsManager.self) private var metricsManager
    @Environment(SettingsManager.self) private var settingsManager

    // Real-time vitals
    @State private var vitals: [VitalsRecord] = []
    @State private var isLoadingVitals = false
    @State private var showRawData = false

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
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(40)
                } else {
                    // Sleep summary
                    SleepSummaryCardView()

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

                    // Raw data section
                    rawDataSection

                    // Calibration warning
                    calibrationWarning
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .refreshable { await refresh() }
        .task { await refresh() }
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

    // MARK: - Raw Data Section

    private var rawDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) { showRawData.toggle() }
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
                        Text("\(vitals.count) data points · \(selectedSide.displayName) side")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(showRawData ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showRawData {
                VStack(spacing: 4) {
                    let filtered = smoothedVitals.count
                    let total = vitals.count
                    let dropped = total - filtered

                    HStack(spacing: 8) {
                        Text("Total records")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                        Text("\(total)")
                            .font(.caption.monospaced())
                            .foregroundColor(Theme.textSecondary)
                    }
                    HStack(spacing: 8) {
                        Text("After filtering")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                        Text("\(filtered)")
                            .font(.caption.monospaced())
                            .foregroundColor(Theme.textSecondary)
                    }
                    if dropped > 0 {
                        HStack(spacing: 8) {
                            Text("Outliers removed")
                                .font(.caption)
                                .foregroundColor(Theme.amber)
                            Spacer()
                            Text("\(dropped)")
                                .font(.caption.monospaced())
                                .foregroundColor(Theme.amber)
                        }
                    }
                }
                .padding(.leading, 44)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }

    // MARK: - Calibration Warning

    private var calibrationWarning: some View {
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
        .padding(12)
        .background(Theme.amber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.amber.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Fetch

    private func refresh() async {
        await metricsManager.fetchAll()
        await fetchVitals()
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
                    Task { await metricsManager.fetchAll() }
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

    @State private var selectedRecord: VitalsRecord?

    private var dataPoints: [(Date, Double)] {
        records.compactMap { r in
            r[keyPath: valueKey].map { (r.date, $0) }
        }
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

                // Show selected value or latest
                if let sel = selectedRecord, let val = sel[keyPath: valueKey] {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(val)) \(unit)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(color)
                        Text(sel.timeLabel)
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                    }
                } else if let last = dataPoints.last {
                    Text("\(Int(last.1)) \(unit)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(color)
                }
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
                    if let avg = average {
                        RuleMark(y: .value("Avg", avg))
                            .foregroundStyle(color.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .leading) {
                                Text("avg")
                                    .font(.system(size: 8))
                                    .foregroundColor(color.opacity(0.5))
                            }
                    }

                    // Data line
                    ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value(title, point.1)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        AreaMark(
                            x: .value("Time", point.0),
                            y: .value(title, point.1)
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

                    // Selection indicator
                    if let sel = selectedRecord, let val = sel[keyPath: valueKey] {
                        PointMark(
                            x: .value("Time", sel.date),
                            y: .value(title, val)
                        )
                        .foregroundStyle(.white)
                        .symbolSize(40)

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
                .chartXSelection(value: $selectedRecord.date)
                .frame(height: 180)
            }
        }
        .cardStyle()
    }
}

// MARK: - Selection Binding Helper

private extension Binding where Value == VitalsRecord? {
    var date: Binding<Date?> {
        Binding<Date?>(
            get: { wrappedValue?.date },
            set: { _ in }
        )
    }
}
