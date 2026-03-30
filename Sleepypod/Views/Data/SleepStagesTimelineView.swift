import SwiftUI
import Charts

struct SleepStagesTimelineView: View {
    let stages: [SleepAnalyzer.SleepEpoch]
    let qualityScore: Int?
    @Environment(MetricsManager.self) private var metricsManager

    @State private var selectedDate: Date?
    @State private var scoreAnimated = false

    // Hypnogram Y ordering: Wake at top (3), Deep at bottom (0)
    private static let stageOrder: [SleepAnalyzer.SleepStage: Int] = [
        .deep: 0, .light: 1, .rem: 2, .wake: 3
    ]

    private static let stageLabels: [Int: String] = [
        0: "Deep", 1: "Light", 2: "REM", 3: "Awake"
    ]

    private var selectedEpoch: SleepAnalyzer.SleepEpoch? {
        guard let date = selectedDate else { return nil }
        return stages.min(by: {
            abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
        })
    }

    // Merge consecutive same-stage epochs into blocks
    private var mergedBlocks: [StageBlock] {
        guard !stages.isEmpty else { return [] }
        let sorted = stages.sorted { $0.start < $1.start }
        var blocks: [StageBlock] = []
        var current = sorted[0]
        var blockStart = current.start
        var blockEnd = current.start.addingTimeInterval(current.duration)

        for i in 1..<sorted.count {
            let epoch = sorted[i]
            if epoch.stage == current.stage {
                blockEnd = epoch.start.addingTimeInterval(epoch.duration)
            } else {
                blocks.append(StageBlock(
                    start: blockStart, end: blockEnd,
                    stage: current.stage,
                    yValue: Self.stageOrder[current.stage] ?? 1
                ))
                current = epoch
                blockStart = epoch.start
                blockEnd = epoch.start.addingTimeInterval(epoch.duration)
            }
        }
        blocks.append(StageBlock(
            start: blockStart, end: blockEnd,
            stage: current.stage,
            yValue: Self.stageOrder[current.stage] ?? 1
        ))
        return blocks
    }

    private func stageDuration(_ stage: SleepAnalyzer.SleepStage) -> String {
        let total = stages.filter { $0.stage == stage }.reduce(0.0) { $0 + $1.duration }
        let minutes = Int(total / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    private func stagePct(_ stage: SleepAnalyzer.SleepStage) -> Int {
        guard !stages.isEmpty else { return 0 }
        return Int(Double(stages.filter { $0.stage == stage }.count) / Double(stages.count) * 100)
    }

    private var scoreColor: Color {
        guard let score = qualityScore else { return Theme.textMuted }
        if score >= 80 { return Theme.healthy }
        if score >= 60 { return Theme.accent }
        if score >= 40 { return Theme.amber }
        return Theme.error
    }

    private var scoreLabel: String {
        guard let score = qualityScore else { return "" }
        if score >= 85 { return "Excellent" }
        if score >= 70 { return "Good" }
        if score >= 50 { return "Fair" }
        return "Poor"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stages.isEmpty {
                // Empty / fallback
                Text(stages.isEmpty ? "BED PRESENCE" : "SLEEP STAGES")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)

                if let record = metricsManager.selectedDayRecord,
                   !parsePresenceIntervals(record).isEmpty {
                    presenceChart(record)
                } else {
                    Text("Vitals data needed for sleep staging")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            } else {
                // MARK: - Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "brain")
                                .font(.caption)
                                .foregroundColor(Theme.purple)
                            Text("SLEEP ANALYSIS")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                                .tracking(1)
                        }
                        Text("sleepypod")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                    }

                    Spacer()

                    // Tooltip when tapped, score when idle
                    if let epoch = selectedEpoch {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(epoch.stage.rawValue)
                                .font(.caption.weight(.medium))
                                .foregroundColor(stageColor(epoch.stage))
                            HStack(spacing: 6) {
                                Text("\(Int(epoch.heartRate)) BPM")
                                    .font(.caption2)
                                if let hrv = epoch.hrv {
                                    Text("\(Int(hrv)) ms")
                                        .font(.caption2)
                                }
                                if let br = epoch.breathingRate {
                                    Text("\(Int(br)) BR")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(Theme.textMuted)
                        }
                    } else if let score = qualityScore {
                        ZStack {
                            Circle()
                                .stroke(scoreColor.opacity(0.15), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: scoreAnimated ? Double(score) / 100.0 : 0)
                                .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeOut(duration: 1.0), value: scoreAnimated)
                            VStack(spacing: -1) {
                                Text("\(score)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(scoreColor)
                                Text(scoreLabel)
                                    .font(.system(size: 6, weight: .medium))
                                    .foregroundColor(scoreColor.opacity(0.8))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .onAppear { scoreAnimated = true }
                    }
                }

                // MARK: - Stage distribution bar
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        let total = max(stages.count, 1)
                        stageBar(pct: Double(stages.filter { $0.stage == .deep }.count) / Double(total),
                                 color: stageColor(.deep), width: geo.size.width)
                        stageBar(pct: Double(stages.filter { $0.stage == .light }.count) / Double(total),
                                 color: stageColor(.light), width: geo.size.width)
                        stageBar(pct: Double(stages.filter { $0.stage == .rem }.count) / Double(total),
                                 color: stageColor(.rem), width: geo.size.width)
                        stageBar(pct: Double(stages.filter { $0.stage == .wake }.count) / Double(total),
                                 color: stageColor(.wake), width: geo.size.width)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)

                // Percentage legend
                HStack(spacing: 12) {
                    pctLegend(.deep)
                    pctLegend(.light)
                    pctLegend(.rem)
                    pctLegend(.wake)
                }
                .frame(maxWidth: .infinity)

                // MARK: - Hypnogram
                Chart {
                    ForEach(mergedBlocks) { block in
                        RectangleMark(
                            xStart: .value("Start", block.start),
                            xEnd: .value("End", block.end),
                            yStart: .value("Stage", block.yValue),
                            yEnd: .value("StageTop", block.yValue + 1)
                        )
                        .foregroundStyle(stageColor(block.stage))
                        .cornerRadius(2)
                    }

                    if let epoch = selectedEpoch {
                        let yMid = Double(Self.stageOrder[epoch.stage] ?? 1) + 0.5
                        RuleMark(x: .value("Time", epoch.start))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        PointMark(
                            x: .value("Time", epoch.start),
                            y: .value("Stage", yMid)
                        )
                        .foregroundStyle(.white)
                        .symbolSize(50)
                    }
                }
                .chartYScale(domain: 0...4)
                .chartYAxis {
                    AxisMarks(values: [0.5, 1.5, 2.5, 3.5]) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self), let label = Self.stageLabels[Int(v - 0.5)] {
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.textSecondary)
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
                .chartOverlay { proxy in
                    GeometryReader { _ in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let date: Date = proxy.value(atX: location.x) else { return }
                                Haptics.light()
                                if selectedDate != nil && abs((selectedDate ?? .distantPast).timeIntervalSince(date)) < 120 {
                                    selectedDate = nil
                                } else {
                                    selectedDate = date
                                }
                            }
                    }
                }
                .frame(height: 140)

                // Duration legend — centered
                HStack(spacing: 16) {
                    durationLegend(.deep)
                    durationLegend(.light)
                    durationLegend(.rem)
                    durationLegend(.wake)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
    }

    // MARK: - Subviews

    private func stageBar(pct: Double, color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width * pct - 1, 0))
    }

    private func pctLegend(_ stage: SleepAnalyzer.SleepStage) -> some View {
        HStack(spacing: 4) {
            Circle().fill(stageColor(stage)).frame(width: 6, height: 6)
            Text("\(stage.rawValue) \(stagePct(stage))%")
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func durationLegend(_ stage: SleepAnalyzer.SleepStage) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(stageColor(stage))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(stage.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Theme.textSecondary)
                Text(stageDuration(stage))
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    private func stageColor(_ stage: SleepAnalyzer.SleepStage) -> Color {
        Color(hex: stage.color)
    }

    // MARK: - Presence Fallback

    private func presenceChart(_ record: SleepRecord) -> some View {
        let entries = parsePresenceIntervals(record)
        return Group {
            if entries.isEmpty {
                Text("No sleep data available")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(entries) { entry in
                    RectangleMark(
                        xStart: .value("Start", entry.startDate),
                        xEnd: .value("End", entry.endDate),
                        y: .value("State", entry.state)
                    )
                    .foregroundStyle(entry.color)
                    .cornerRadius(2)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let state = value.as(String.self) {
                                Text(state)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(height: 80)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.purple).frame(width: 6, height: 6)
                        Text("In Bed").font(.caption2).foregroundColor(Theme.textSecondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Theme.textMuted).frame(width: 6, height: 6)
                        Text("Out of Bed").font(.caption2).foregroundColor(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }

    private func parsePresenceIntervals(_ record: SleepRecord) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []

        if let data = record.presentIntervals?.data(using: .utf8),
           let intervals = try? JSONDecoder().decode([[Int]].self, from: data) {
            for interval in intervals {
                guard interval.count >= 2 else { continue }
                entries.append(TimelineEntry(
                    startDate: Date(timeIntervalSince1970: TimeInterval(interval[0])),
                    endDate: Date(timeIntervalSince1970: TimeInterval(interval[1])),
                    state: "In Bed", color: Theme.purple))
            }
        }

        if let data = record.notPresentIntervals?.data(using: .utf8),
           let intervals = try? JSONDecoder().decode([[Int]].self, from: data) {
            for interval in intervals {
                guard interval.count >= 2 else { continue }
                entries.append(TimelineEntry(
                    startDate: Date(timeIntervalSince1970: TimeInterval(interval[0])),
                    endDate: Date(timeIntervalSince1970: TimeInterval(interval[1])),
                    state: "Out of Bed", color: Theme.textMuted))
            }
        }

        return entries.sorted { $0.startDate < $1.startDate }
    }
}

// MARK: - Supporting Types

private struct StageBlock: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let stage: SleepAnalyzer.SleepStage
    let yValue: Int
}

struct TimelineEntry: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let state: String
    let color: Color
}
