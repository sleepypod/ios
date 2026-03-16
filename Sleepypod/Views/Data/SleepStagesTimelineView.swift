import SwiftUI
import Charts

struct SleepStagesTimelineView: View {
    let stages: [SleepAnalyzer.SleepEpoch]
    @Environment(MetricsManager.self) private var metricsManager

    @State private var selectedDate: Date?

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

    // Merge consecutive same-stage epochs into blocks for cleaner rendering
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
                    start: blockStart,
                    end: blockEnd,
                    stage: current.stage,
                    yValue: Self.stageOrder[current.stage] ?? 1
                ))
                current = epoch
                blockStart = epoch.start
                blockEnd = epoch.start.addingTimeInterval(epoch.duration)
            }
        }
        blocks.append(StageBlock(
            start: blockStart,
            end: blockEnd,
            stage: current.stage,
            yValue: Self.stageOrder[current.stage] ?? 1
        ))
        return blocks
    }

    // Stage durations for legend
    private func stageDuration(_ stage: SleepAnalyzer.SleepStage) -> String {
        let total = stages.filter { $0.stage == stage }.reduce(0.0) { $0 + $1.duration }
        let minutes = Int(total / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(stages.isEmpty ? "BED PRESENCE" : "SLEEP STAGES")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
                Spacer()

                // Tooltip for selected epoch
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
                }
            }

            if stages.isEmpty {
                // Fallback: presence intervals from sleep detector
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
                // Hypnogram
                Chart(mergedBlocks) { block in
                    RectangleMark(
                        xStart: .value("Start", block.start),
                        xEnd: .value("End", block.end),
                        yStart: .value("Stage", block.yValue),
                        yEnd: .value("StageTop", block.yValue + 1)
                    )
                    .foregroundStyle(stageColor(block.stage))
                    .cornerRadius(2)

                    // Selection indicator
                    if let date = selectedDate {
                        RuleMark(x: .value("Selected", date))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1))
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
                    GeometryReader { geo in
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

                // Legend with durations
                HStack(spacing: 12) {
                    legendItem(.deep)
                    legendItem(.light)
                    legendItem(.rem)
                    legendItem(.wake)
                }
                .padding(.top, 2)
            }
        }
        .cardStyle()
    }

    private func legendItem(_ stage: SleepAnalyzer.SleepStage) -> some View {
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
                let start = Date(timeIntervalSince1970: TimeInterval(interval[0]))
                let end = Date(timeIntervalSince1970: TimeInterval(interval[1]))
                entries.append(TimelineEntry(startDate: start, endDate: end, state: "In Bed", color: Theme.purple))
            }
        }

        if let data = record.notPresentIntervals?.data(using: .utf8),
           let intervals = try? JSONDecoder().decode([[Int]].self, from: data) {
            for interval in intervals {
                guard interval.count >= 2 else { continue }
                let start = Date(timeIntervalSince1970: TimeInterval(interval[0]))
                let end = Date(timeIntervalSince1970: TimeInterval(interval[1]))
                entries.append(TimelineEntry(startDate: start, endDate: end, state: "Out of Bed", color: Theme.textMuted))
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
