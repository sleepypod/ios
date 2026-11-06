import SwiftUI
import Charts

/// The Night at regular width: stages, heart rate, HRV, breathing and movement as stacked lanes over one time
/// axis, the in-bed range. Touching any lane marks the same moment in all of them.
struct NightStackView: View {
    let record: SleepRecord
    let stages: [SleepAnalyzer.SleepEpoch]
    let vitals: [VitalsRecord]
    let side: Side
    var source: SleepAnalyzer.StageSource = .rules
    var modelName: String?
    @State private var selection: Date?

    private let order: [SleepAnalyzer.SleepStage] = [.wake, .rem, .light, .deep]
    private var domain: ClosedRange<Date> {
        record.enteredBedDate...max(record.enteredBedDate.addingTimeInterval(60), record.leftBedDate)
    }
    private var lane: NightLaneContext { NightLaneContext(domain: domain, selection: $selection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Eyebrow("NIGHT")
                if let selection {
                    Text(selection.formatted(date: .omitted, time: .shortened))
                        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text1)
                }
                Spacer(minLength: 8)
                legend
                if source == .model { StageSourceBadge(.model(modelName ?? "model")) }
            }
            NightLane(title: "STAGES", value: stageValue.value, unit: stageValue.unit, height: 88) { stagesChart }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stages, \(stageSummary)")
            vitalLane("HR", unit: "bpm", key: \.heartRate, decimals: 0, color: Theme.red)
            vitalLane("HRV", unit: "ms", key: \.hrv, decimals: 0, color: Theme.cool)
            vitalLane("BREATH", unit: "br/min", key: \.breathingRate, decimals: 1, color: Theme.green)
            PodMovementCardView(record: record, side: side, lane: lane)
            NightTimeAxis(domain: domain)
                .padding(.leading, NightLane<EmptyView>.labelWidth + NightLane<EmptyView>.spacing)
        }
        .cardStyle(vertical: 18, horizontal: 20)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(order, id: \.self) { stage in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(stage.displayColor).frame(width: 7, height: 7)
                    Text(stage.label)
                }
            }
        }
        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
        .accessibilityHidden(true)
    }

    // MARK: Stages

    private var segments: [SleepStagesTimelineView.Segment] { SleepStagesTimelineView.segments(stages) }

    private var stagesChart: some View {
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if let index = order.firstIndex(of: segment.stage) {
                    // Awake on top, deep at the bottom, as in the compact hypnogram.
                    let top = Double(order.count - index)
                    RectangleMark(xStart: .value("Start", segment.start), xEnd: .value("End", segment.end),
                                  yStart: .value("Lane", top - 0.8), yEnd: .value("Lane", top - 0.2))
                        .foregroundStyle(segment.stage.displayColor)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            if let selection { NightLaneSelection(date: selection) }
        }
        .chartYScale(domain: 0...Double(order.count))
        .nightLane(lane)
    }

    private var stageValue: (value: String, unit: String) {
        if let selection, let segment = segments.first(where: { $0.start <= selection && selection < $0.end }) {
            return (segment.stage.label, "stage")
        }
        let deep = segments.filter { $0.stage == .deep }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return segments.isEmpty ? ("—", "stages") : (DisplayTime.duration(Int(deep)), "deep")
    }

    private var stageSummary: String {
        guard !segments.isEmpty else { return "not enough data" }
        return order.map { stage in
            let seconds = segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            return "\(stage.label) \(DisplayTime.duration(Int(seconds)))"
        }.joined(separator: ", ")
    }

    // MARK: Vitals

    private func vitalLane(_ title: String, unit: String, key: KeyPath<VitalsRecord, Double?>, decimals: Int,
                           color: Color) -> some View {
        let points = vitals.compactMap { record in record[keyPath: key].map { (date: record.date, value: $0) } }
            .sorted { $0.date < $1.date }
        let values = points.map(\.value)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let selected = selection.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                .flatMap { abs($0.date.timeIntervalSince(date)) <= 600 ? $0.value : nil }
        }
        let shown = selection == nil ? average : selected
        let display = shown.map { String(format: "%.\(decimals)f", $0) } ?? "—"
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.15, 1)
        return NightLane(title: title, value: display, unit: unit, color: color) {
            if points.isEmpty {
                Text("No data").font(.caption).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(points, id: \.date) { point in
                        LineMark(x: .value("Time", point.date), y: .value(title, point.value))
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                    if let average {
                        RuleMark(y: .value("Average", average))
                            .foregroundStyle(color.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    if let selection { NightLaneSelection(date: selection) }
                }
                .chartYScale(domain: (low - pad)...(high + pad))
                .nightLane(lane)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), average \(average.map { String(format: "%.\(decimals)f", $0) } ?? "unavailable") \(unit)")
    }
}

/// What a lane needs from the stack: the shared time domain and the moment being inspected.
struct NightLaneContext {
    let domain: ClosedRange<Date>
    let selection: Binding<Date?>
}

/// One row of the stack: a fixed-width label column (name, value, unit) and a chart sharing the time axis.
struct NightLane<Plot: View>: View {
    static var labelWidth: CGFloat { 96 }
    static var spacing: CGFloat { 14 }
    let title: String
    let value: String
    let unit: String
    var color: Color?
    var note: String?
    var noteColor: Color = Theme.text3
    var height: CGFloat = 76
    @ViewBuilder var plot: Plot

    var body: some View {
        HStack(spacing: Self.spacing) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if let color { Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true) }
                    Eyebrow(title, size: 10)
                }
                Text(value).font(.mono(20, weight: .light, relativeTo: .title3)).foregroundStyle(Theme.text1)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text(unit).foregroundStyle(Theme.text3)
                    if let note { Text(note).foregroundStyle(noteColor) }
                }
                .font(.mono(10, relativeTo: .caption2)).lineLimit(1)
            }
            .frame(width: Self.labelWidth, alignment: .leading)
            plot.frame(maxWidth: .infinity).frame(height: height)
        }
    }
}

/// The inspected moment, drawn the same way in every lane.
struct NightLaneSelection: ChartContent {
    let date: Date
    var body: some ChartContent {
        RuleMark(x: .value("Time", date))
            .foregroundStyle(Theme.text1.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1))
    }
}

extension View {
    /// The shared lane look: the stack's time domain, hourly gridlines, no axis labels (the stack draws one axis),
    /// and selection bound to the stack.
    func nightLane(_ lane: NightLaneContext) -> some View {
        chartXScale(domain: lane.domain)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.cardBorder)
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: lane.selection)
    }
}

/// Hour labels under the stack, placed by the same domain the lanes use.
struct NightTimeAxis: View {
    let domain: ClosedRange<Date>

    private var hours: [Date] {
        let calendar = Calendar.current
        guard var hour = calendar.nextDate(after: domain.lowerBound, matching: DateComponents(minute: 0, second: 0),
                                           matchingPolicy: .nextTime) else { return [] }
        var result: [Date] = []
        while hour < domain.upperBound {
            result.append(hour)
            hour = hour.addingTimeInterval(3600)
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
            ForEach(hours, id: \.self) { hour in
                let x = geo.size.width * hour.timeIntervalSince(domain.lowerBound) / total
                if x > 18 && x < geo.size.width - 18 {
                    let minutes = Calendar.current.component(.hour, from: hour) * 60
                    Text(DisplayTime.tick(minutes: minutes))
                        .font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                        .fixedSize()
                        .position(x: x, y: geo.size.height / 2)
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
