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

    private let order: [SleepAnalyzer.SleepStage] = [.wake, .rem, .light, .deep]
    private static let watchColor = Theme.text2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(record.enteredBedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2).padding(.horizontal, 4)
                if let comparison, comparison.hasWatchData {
                    agreementCard(comparison)
                    timelinesCard(comparison)
                    if !comparison.stages.disagreements.isEmpty { disagreementsCard(comparison.stages) }
                    heartRateCard(comparison)
                    averagesLayout {
                        averageCard("HRV", unit: "ms", icon: "waveform.path.ecg", color: Theme.cool, decimals: 0, averages: comparison.hrv)
                        averageCard("BREATH", unit: "br/min", icon: "lungs", color: Theme.green, decimals: 1, averages: comparison.breathing)
                    }
                    Text("The Watch writes HRV as SDNN from a few spot readings a night, so night averages are the fair comparison. Agreement counts only minutes where the Watch recorded a stage.")
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

    private func timelinesCard(_ comparison: WatchComparison) -> some View {
        let ours = SleepStagesTimelineView.segments(epochs)
        let theirs = WatchComparison.merged(comparison.watchStages).map { SleepStagesTimelineView.Segment(stage: $0.stage, start: $0.start, end: $0.end) }
        let start = min(ours.first?.start ?? record.enteredBedDate, theirs.first?.start ?? record.enteredBedDate)
        let end = max(ours.map(\.end).max() ?? record.leftBedDate, theirs.map(\.end).max() ?? record.leftBedDate)
        let total = max(1, end.timeIntervalSince(start))
        return VStack(alignment: .leading, spacing: 12) {
            lanes("SLEEPYPOD", segments: ours, start: start, total: total)
            lanes("APPLE WATCH", segments: theirs, start: start, total: total)
            HStack {
                Text(start, format: .dateTime.hour().minute())
                Spacer()
                Text(end, format: .dateTime.hour().minute())
            }
            .font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3).accessibilityHidden(true)
            legend
        }
        .cardStyle()
    }

    private func lanes(_ title: String, segments: [SleepStagesTimelineView.Segment], start: Date, total: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title, size: 10)
            if segments.isEmpty {
                Text("No stages recorded").font(.footnote).foregroundStyle(Theme.text2).frame(height: 68)
            } else {
                Canvas { context, size in
                    for segment in segments {
                        guard let lane = order.firstIndex(of: segment.stage) else { continue }
                        let x = size.width * segment.start.timeIntervalSince(start) / total
                        let width = max(2, size.width * segment.end.timeIntervalSince(segment.start) / total)
                        let rect = CGRect(x: x, y: CGFloat(lane) * 17 + 1, width: width, height: 11)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(segment.stage.displayColor))
                    }
                }
                .frame(height: 68)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title.capitalized) stages, \(summary(segments))")
    }

    private func summary(_ segments: [SleepStagesTimelineView.Segment]) -> String {
        segments.isEmpty ? "none recorded" : order.map { stage in
            let seconds = segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            return "\(stage.label) \(DisplayTime.duration(Int(seconds)))"
        }.joined(separator: ", ")
    }

    private var legend: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(order, id: \.self) { stage in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(stage.displayColor).frame(width: 7, height: 7)
                    Text(stage.label)
                }
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
            }
        }
        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
        .accessibilityHidden(true)
    }

    private func disagreementsCard(_ stages: WatchComparison.StageAgreement) -> some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("WHERE THEY DIFFER")
                Text("What sleepypod called, and what the Watch called for the same minutes.")
                    .font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(stages.disagreements.prefix(4)) { item in
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        stageChip(item.ours)
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                        stageChip(item.watch)
                    }
                    Spacer(minLength: 8)
                    RowValue(DisplayTime.duration(Int(item.seconds)), mono: true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("sleepypod \(item.ours.label), Watch \(item.watch.label), \(DisplayTime.duration(Int(item.seconds)))")
            }
        }
    }

    private func stageChip(_ stage: SleepAnalyzer.SleepStage) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(stage.displayColor).frame(width: 7, height: 7)
            Text(stage.label).font(.subheadline).foregroundStyle(Theme.text1)
        }
    }

    // MARK: Vitals

    private func heartRateCard(_ comparison: WatchComparison) -> some View {
        let ours = vitals.compactMap { v in v.heartRate.map { WatchComparison.Reading(date: v.date, value: $0) } }.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "heart").font(.caption).foregroundStyle(Theme.red)
                    Eyebrow("HEART RATE")
                }
                Spacer()
                if let error = comparison.heartRateError, let bias = comparison.heartRateBias {
                    Text("±\(String(format: "%.1f", error)) · bias \(bias >= 0 ? "+" : "")\(String(format: "%.1f", bias)) bpm")
                        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                }
            }
            if comparison.watchHeartRate.isEmpty {
                Text("The Watch recorded no heart rate this night").font(.subheadline).foregroundStyle(Theme.text2)
            } else {
                Chart {
                    ForEach(ours) { reading in
                        LineMark(x: .value("Time", reading.date), y: .value("bpm", reading.value), series: .value("Source", "sleepypod"))
                            .foregroundStyle(Theme.red).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    ForEach(comparison.watchHeartRate) { reading in
                        LineMark(x: .value("Time", reading.date), y: .value("bpm", reading.value), series: .value("Source", "Apple Watch"))
                            .foregroundStyle(Self.watchColor).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("Time", reading.date), y: .value("bpm", reading.value))
                            .foregroundStyle(Self.watchColor).symbolSize(10)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.border1)
                        AxisValueLabel {
                            if let bpm = value.as(Double.self) {
                                Text("\(Int(bpm))").font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.hour()).font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                }
                .frame(height: 150)
                .accessibilityElement()
                .accessibilityLabel(heartRateSummary(comparison))
                HStack(spacing: 14) {
                    seriesKey("sleepypod", color: Theme.red)
                    seriesKey("Apple Watch", color: Self.watchColor)
                    Spacer()
                    Text("\(comparison.heartRate.count) matched").font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                }
                .accessibilityHidden(true)
            }
        }
        .cardStyle()
    }

    private func heartRateSummary(_ comparison: WatchComparison) -> String {
        guard let error = comparison.heartRateError, let bias = comparison.heartRateBias else { return "Heart rate, no matched readings" }
        return "Heart rate, \(comparison.heartRate.count) matched readings, average error \(String(format: "%.1f", error)) beats per minute, " +
            "sleepypod reads \(String(format: "%.1f", abs(bias))) \(bias >= 0 ? "higher" : "lower") than the Watch"
    }

    private func seriesKey(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(title)
        }
        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
    }

    private var averagesLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
    }

    private func averageCard(_ title: String, unit: String, icon: String, color: Color, decimals: Int,
                             averages: WatchComparison.Averages) -> some View {
        func text(_ value: Double?) -> String { value.map { String(format: "%.\(decimals)f", $0) } ?? "—" }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
                Eyebrow(title, size: 10)
            }
            pair("sleepypod", value: text(averages.ours))
            pair("Watch", value: text(averages.watch))
            Text(averages.difference.map { "\($0 >= 0 ? "+" : "")\(String(format: "%.\(decimals)f", $0)) \(unit)" } ?? "Night average, \(unit)")
                .font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
        }
        .cardStyle(radius: 18, vertical: 14, horizontal: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), sleepypod \(text(averages.ours)) \(unit), Watch \(text(averages.watch)) \(unit)")
    }

    private func pair(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(.mono(20, weight: .light, relativeTo: .title3)).foregroundStyle(Theme.text1)
        }
    }
}
