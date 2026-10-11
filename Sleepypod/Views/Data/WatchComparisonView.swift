import SwiftUI
import Charts

/// One night of the pod's stages and vitals set against what an Apple Watch recorded on the same side.
struct WatchComparisonView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(HealthSyncService.self) private var health
    let record: SleepRecord
    let epochs: [SleepAnalyzer.SleepEpoch]
    let vitals: [VitalsRecord]
    @State private var comparison: WatchComparison?
    @State private var loaded = false
    /// The touched minute, shared so every chart marks the same moment.
    @State private var selection: Date?

    private let order: [SleepAnalyzer.SleepStage] = [.wake, .rem, .light, .deep]
    private static let watchColor = Theme.text2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(record.enteredBedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2).padding(.horizontal, 4)
                if let comparison, comparison.hasWatchData {
                    agreementCard(comparison)
                    stagesCard(comparison)
                    if comparison.stages.comparedSeconds > 0 { confusionCard(comparison.stages) }
                    vitalCard(heartRateMetric(comparison))
                    vitalCard(hrvMetric(comparison))
                    vitalCard(breathingMetric(comparison))
                    Text("Touch and hold any chart to read both sources at that minute. sleepypod reports HRV as RMSSD and the Watch as SDNN from a few spot readings, so compare how they move, not their level. Agreement counts only minutes where the Watch recorded a stage.")
                        .font(.footnote).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                } else if loaded {
                    ContentUnavailableView("No Apple Watch data", systemImage: "applewatch",
                                           description: Text("Wear your Watch to bed with Sleep tracking on, and allow sleepypod to read Sleep, Heart Rate, HRV and Respiratory Rate in Health."))
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: record.id) {
            comparison = APIBackend.current.isDemo
                ? WatchComparison.demo(record: record, epochs: epochs, vitals: vitals)
                : await health.watchComparison(record: record, epochs: epochs, vitals: vitals)
            loaded = true
        }
    }

    // MARK: Stages

    private func agreementCard(_ comparison: WatchComparison) -> some View {
        let stages = comparison.stages
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("STAGE AGREEMENT")
                Text(stages.percent.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.mono(34, weight: .light, relativeTo: .largeTitle)).foregroundStyle(Theme.text1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(stages.comparedSeconds > 0 ? "\(DisplayTime.duration(Int(stages.comparedSeconds))) compared" : "No overlapping stages")
                Text(stages.comparedSeconds > 0 ? "\(DisplayTime.duration(Int(stages.matchedSeconds))) matched" : "")
            }
            .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var nightStart: Date {
        min(epochs.map(\.start).min() ?? record.enteredBedDate, comparison?.watchStages.first?.start ?? record.enteredBedDate)
    }
    private var nightEnd: Date {
        max(epochs.map { $0.start.addingTimeInterval($0.duration) }.max() ?? record.leftBedDate,
            comparison?.watchStages.map(\.end).max() ?? record.leftBedDate)
    }

    /// Hypnogram lanes, deepest at the bottom.
    private static func lane(_ stage: SleepAnalyzer.SleepStage) -> Double {
        switch stage {
        case .wake: 3
        case .rem: 2
        case .light: 1
        case .deep: 0
        }
    }

    /// sleepypod's stages as coloured blocks with the Watch's hypnogram drawn through them, so a line
    /// leaving its block is a disagreement at that minute. The strip beneath marks every compared minute.
    private func stagesCard(_ comparison: WatchComparison) -> some View {
        let ours = SleepStagesTimelineView.segments(epochs).map { WatchComparison.StageSample(start: $0.start, end: $0.end, stage: $0.stage) }
        let theirs = WatchComparison.merged(comparison.watchStages, maxGap: 0)
        let agreement = agreementRuns(theirs)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("STAGES")
                Spacer()
                if let selection {
                    let pod = WatchComparison.stage(at: selection, in: ours)
                    let watch = WatchComparison.stage(at: selection, in: theirs)
                    Text("\(selection.formatted(date: .omitted, time: .shortened))  ·  \(pod?.label ?? "—") / \(watch?.label ?? "—")")
                        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text1)
                }
            }
            Chart {
                ForEach(Array(ours.enumerated()), id: \.offset) { _, segment in
                    RectangleMark(xStart: .value("Start", segment.start), xEnd: .value("End", segment.end),
                                  yStart: .value("Lane", Self.lane(segment.stage) - 0.34), yEnd: .value("Lane", Self.lane(segment.stage) + 0.34))
                        .foregroundStyle(segment.stage.displayColor.opacity(0.75))
                }
                ForEach(Array(theirs.enumerated()), id: \.offset) { index, segment in
                    LineMark(x: .value("Time", segment.start), y: .value("Lane", Self.lane(segment.stage)), series: .value("Watch", index))
                        .foregroundStyle(Theme.text1).lineStyle(StrokeStyle(lineWidth: 1.5))
                    LineMark(x: .value("Time", segment.end), y: .value("Lane", Self.lane(segment.stage)), series: .value("Watch", index))
                        .foregroundStyle(Theme.text1).lineStyle(StrokeStyle(lineWidth: 1.5))
                    if index + 1 < theirs.count, theirs[index + 1].start.timeIntervalSince(segment.end) <= 300 {
                        RuleMark(x: .value("Time", theirs[index + 1].start),
                                 yStart: .value("Lane", Self.lane(segment.stage)), yEnd: .value("Lane", Self.lane(theirs[index + 1].stage)))
                            .foregroundStyle(Theme.text1).lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                if let selection { selectionRule(selection) }
            }
            .chartXScale(domain: nightStart...nightEnd)
            .chartYScale(domain: -0.5...3.5)
            .chartXSelection(value: $selection)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 1, 2, 3]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.border1)
                    AxisValueLabel {
                        if let lane = value.as(Double.self), let stage = order.first(where: { Self.lane($0) == lane }) {
                            Text(stage.label).font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .chartXAxis { hourAxis }
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stages. sleepypod \(summary(ours)). Apple Watch \(summary(theirs)).")
            Chart {
                ForEach(Array(agreement.enumerated()), id: \.offset) { _, run in
                    RectangleMark(xStart: .value("Start", run.start), xEnd: .value("End", run.end), yStart: .value("Row", 0), yEnd: .value("Row", 1))
                        .foregroundStyle(run.matched ? Theme.green : Theme.amber)
                }
                if let selection { selectionRule(selection) }
            }
            .chartXScale(domain: nightStart...nightEnd)
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartXSelection(value: $selection)
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .accessibilityHidden(true)
            stageLegend
        }
        .cardStyle()
    }

    /// Runs of consecutive compared epochs that agreed or disagreed with the Watch. Gaps up to `maxGap`
    /// are closed, as in the stage lanes, so sparse epochs read as a continuous strip.
    private func agreementRuns(_ watch: [WatchComparison.StageSample], maxGap: TimeInterval = 300) -> [(start: Date, end: Date, matched: Bool)] {
        var runs: [(start: Date, end: Date, matched: Bool)] = []
        for epoch in epochs.sorted(by: { $0.start < $1.start }) {
            let midpoint = epoch.start.addingTimeInterval(epoch.duration / 2)
            guard let theirs = WatchComparison.stage(at: midpoint, in: watch) else { continue }
            let end = epoch.start.addingTimeInterval(epoch.duration)
            let matched = theirs == epoch.stage
            if let last = runs.last, epoch.start.timeIntervalSince(last.end) <= maxGap {
                if last.matched == matched {
                    runs[runs.count - 1].end = end
                    continue
                }
                runs[runs.count - 1].end = epoch.start
            }
            runs.append((epoch.start, end, matched))
        }
        return runs
    }

    private func summary(_ segments: [WatchComparison.StageSample]) -> String {
        segments.isEmpty ? "none recorded" : order.map { stage in
            let seconds = segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            return "\(stage.label) \(DisplayTime.duration(Int(seconds)))"
        }.joined(separator: ", ")
    }

    private var stageLegend: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.cool.opacity(0.75)).frame(width: 12, height: 7)
                Text("sleepypod")
            }
            seriesKey("Apple Watch", color: Theme.text1)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1).fill(Theme.green).frame(width: 7, height: 7)
                Text("Agree")
                RoundedRectangle(cornerRadius: 1).fill(Theme.amber).frame(width: 7, height: 7)
                Text("Differ")
            }
        }
        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
        .accessibilityHidden(true)
    }

    /// Minutes per pair of calls. Rows are sleepypod, columns the Watch; the diagonal is agreement, and a heavy
    /// off-diagonal cell is a systematic bias worth tuning (say, sleepypod calling Light what the Watch calls Deep).
    private func confusionCard(_ stages: WatchComparison.StageAgreement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("MINUTES BY STAGE")
                Text("Rows are what sleepypod called, columns what the Watch called for the same minutes.")
                    .font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(order, id: \.self) { watch in
                        Text(watch.label).font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3).frame(maxWidth: .infinity)
                    }
                }
                ForEach(order, id: \.self) { ours in
                    let rowTotal = order.reduce(0) { $0 + stages.seconds(ours: ours, watch: $1) }
                    GridRow {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(ours.displayColor).frame(width: 7, height: 7)
                            Text(ours.label).font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                        }
                        ForEach(order, id: \.self) { watch in
                            let seconds = stages.seconds(ours: ours, watch: watch)
                            let share = rowTotal > 0 ? seconds / rowTotal : 0
                            Text(seconds > 0 ? "\(Int((seconds / 60).rounded()))" : "·")
                                .font(.mono(13, relativeTo: .footnote)).foregroundStyle(seconds > 0 ? Theme.text1 : Theme.text3)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(seconds > 0 ? (ours == watch ? Theme.green : Theme.amber).opacity(0.12 + 0.5 * share) : Theme.text3.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("sleepypod \(ours.label): " + order.map { watch in
                        "Watch \(watch.label) \(Int((stages.seconds(ours: ours, watch: watch) / 60).rounded())) minutes"
                    }.joined(separator: ", "))
                }
            }
        }
        .cardStyle()
    }

    // MARK: Vitals

    private struct Metric {
        let title: String
        let icon: String
        let color: Color
        let unit: String
        let decimals: Int
        let ours: [WatchComparison.Reading]
        let watch: [WatchComparison.Reading]
        /// How far from the touched minute a Watch reading may be and still be shown.
        let watchTolerance: TimeInterval
        let stat: String?
        let accessibility: String
        let footer: String
    }

    private func podReadings(_ value: (VitalsRecord) -> Double?) -> [WatchComparison.Reading] {
        vitals.compactMap { v in value(v).map { WatchComparison.Reading(date: v.date, value: $0) } }.sorted { $0.date < $1.date }
    }

    private func averagesText(_ averages: WatchComparison.Averages, decimals: Int, unit: String) -> String? {
        guard let ours = averages.ours, let watch = averages.watch else { return nil }
        return "avg \(String(format: "%.\(decimals)f", ours)) / \(String(format: "%.\(decimals)f", watch)) \(unit)"
    }

    private func heartRateMetric(_ comparison: WatchComparison) -> Metric {
        var stat: String?
        if let error = comparison.heartRateError, let bias = comparison.heartRateBias {
            stat = "±\(String(format: "%.1f", error)) · bias \(bias >= 0 ? "+" : "")\(String(format: "%.1f", bias)) bpm"
        }
        return Metric(title: "HEART RATE", icon: "heart", color: Theme.red, unit: "bpm", decimals: 0,
                      ours: podReadings(\.heartRate), watch: comparison.watchHeartRate, watchTolerance: 5 * 60,
                      stat: stat, accessibility: heartRateSummary(comparison), footer: "\(comparison.heartRate.count) matched")
    }

    private func hrvMetric(_ comparison: WatchComparison) -> Metric {
        Metric(title: "HRV", icon: "waveform.path.ecg", color: Theme.cool, unit: "ms", decimals: 0,
               ours: podReadings(\.hrv), watch: comparison.watchHRV, watchTolerance: 20 * 60,
               stat: averagesText(comparison.hrv, decimals: 0, unit: "ms"),
               accessibility: averagesSummary("HRV", comparison.hrv, decimals: 0, unit: "milliseconds"),
               footer: "RMSSD vs SDNN")
    }

    private func breathingMetric(_ comparison: WatchComparison) -> Metric {
        Metric(title: "BREATHING", icon: "lungs", color: Theme.green, unit: "br/min", decimals: 1,
               ours: podReadings(\.breathingRate), watch: comparison.watchBreathing, watchTolerance: 20 * 60,
               stat: averagesText(comparison.breathing, decimals: 1, unit: "br/min"),
               accessibility: averagesSummary("Breathing rate", comparison.breathing, decimals: 1, unit: "breaths per minute"),
               footer: "\(comparison.watchBreathing.count) Watch readings")
    }

    private func vitalCard(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: metric.icon).font(.caption).foregroundStyle(metric.color)
                    Eyebrow(metric.title)
                }
                Spacer()
                if let selection {
                    Text(readout(metric, at: selection)).font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text1)
                } else if let stat = metric.stat {
                    Text(stat).font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                }
            }
            if metric.ours.isEmpty && metric.watch.isEmpty {
                Text("Neither source recorded this night").font(.subheadline).foregroundStyle(Theme.text2)
            } else {
                Chart {
                    ForEach(metric.ours) { reading in
                        LineMark(x: .value("Time", reading.date), y: .value(metric.unit, reading.value), series: .value("Source", "sleepypod"))
                            .foregroundStyle(metric.color).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    ForEach(metric.watch) { reading in
                        // Straight segments: the Watch samples sparsely, and a smoothed curve would invent values between readings.
                        LineMark(x: .value("Time", reading.date), y: .value(metric.unit, reading.value), series: .value("Source", "Apple Watch"))
                            .foregroundStyle(Self.watchColor).lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("Time", reading.date), y: .value(metric.unit, reading.value))
                            .foregroundStyle(Self.watchColor).symbolSize(metric.watch.count < 20 ? 24 : 10)
                    }
                    if let selection {
                        selectionRule(selection)
                        if let pod = WatchComparison.nearest(metric.ours, to: selection, within: 120) {
                            PointMark(x: .value("Time", pod.date), y: .value(metric.unit, pod.value))
                                .foregroundStyle(metric.color).symbolSize(60)
                        }
                        if let watch = WatchComparison.nearest(metric.watch, to: selection, within: metric.watchTolerance) {
                            PointMark(x: .value("Time", watch.date), y: .value(metric.unit, watch.value))
                                .foregroundStyle(Theme.text1).symbolSize(60)
                        }
                    }
                }
                .chartXScale(domain: nightStart...nightEnd)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXSelection(value: $selection)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.border1)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.\(metric.decimals)f", number)).font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                }
                .chartXAxis { hourAxis }
                .frame(height: 150)
                .accessibilityElement()
                .accessibilityLabel(metric.accessibility)
                HStack(spacing: 14) {
                    seriesKey("sleepypod", color: metric.color)
                    seriesKey("Apple Watch", color: Self.watchColor)
                    Spacer()
                    Text(metric.watch.isEmpty ? "No Watch readings" : metric.footer)
                        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                }
                .accessibilityHidden(true)
            }
        }
        .cardStyle()
    }

    private func readout(_ metric: Metric, at date: Date) -> String {
        func text(_ reading: WatchComparison.Reading?) -> String {
            reading.map { String(format: "%.\(metric.decimals)f", $0.value) } ?? "—"
        }
        let pod = WatchComparison.nearest(metric.ours, to: date, within: 120)
        let watch = WatchComparison.nearest(metric.watch, to: date, within: metric.watchTolerance)
        return "\(date.formatted(date: .omitted, time: .shortened))  ·  \(text(pod)) / \(text(watch)) \(metric.unit)"
    }

    private func selectionRule(_ date: Date) -> some ChartContent {
        RuleMark(x: .value("Selected", date)).foregroundStyle(Theme.text3).lineStyle(StrokeStyle(lineWidth: 1))
    }

    private var hourAxis: some AxisContent {
        AxisMarks { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date, format: .dateTime.hour()).font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                }
            }
        }
    }

    private func heartRateSummary(_ comparison: WatchComparison) -> String {
        guard let error = comparison.heartRateError, let bias = comparison.heartRateBias else { return "Heart rate, no matched readings" }
        return "Heart rate, \(comparison.heartRate.count) matched readings, average error \(String(format: "%.1f", error)) beats per minute, " +
            "sleepypod reads \(String(format: "%.1f", abs(bias))) \(bias >= 0 ? "higher" : "lower") than the Watch"
    }

    private func averagesSummary(_ title: String, _ averages: WatchComparison.Averages, decimals: Int, unit: String) -> String {
        func text(_ value: Double?) -> String { value.map { String(format: "%.\(decimals)f", $0) } ?? "not recorded" }
        return "\(title), night average sleepypod \(text(averages.ours)) \(unit), Watch \(text(averages.watch)) \(unit)"
    }

    private func seriesKey(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(title)
        }
        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
    }
}
