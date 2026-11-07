import SwiftUI
import Charts

/// The pod's per-minute movement score across one night, with the Watch's wrist movement drawn over it when a
/// Watch recording covers the same night.
struct PodMovementCardView: View {
    let record: SleepRecord
    let side: Side
    /// Set when drawn as a lane of the wide Night stack instead of its own card.
    var lane: NightLaneContext?
    @Environment(WatchMotionReceiver.self) private var watchMotion
    @Environment(UserProfile.self) private var profile
    @State private var movement: [MovementRecord] = []
    @State private var comparison: WatchMotionComparison?
    @State private var loaded = false
    @State private var error: String?

    /// The Watch recording sharing the most time with this night, if any.
    private var watchRecording: WatchMotionInbox.Recording? {
        func overlap(_ r: WatchMotionInbox.Recording) -> TimeInterval {
            min(r.to, record.leftBedDate).timeIntervalSince(max(r.from, record.enteredBedDate))
        }
        return watchMotion.recordings.filter { overlap($0) > 0 }.max { overlap($0) < overlap($1) }
    }

    var body: some View {
        content.task(id: "\(record.id)-\(side.rawValue)-\(watchMotion.recordings.count)") { await load() }
    }

    @ViewBuilder private var content: some View {
        if let lane { laneRow(lane) } else { card }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow("MOVEMENT")
                Spacer()
                if loaded && !movement.isEmpty {
                    Text("\(movement.count) min").font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                }
            }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if movement.isEmpty {
                Text(error ?? "No movement recorded for this night")
                    .font(.subheadline).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
                if let comparison {
                    HStack(spacing: 14) {
                        legend("Pod", color: Theme.amber)
                        legend("Watch", color: Theme.cool)
                        Spacer()
                        if let r = comparison.correlation {
                            Text("r \(r.formatted(.number.precision(.fractionLength(2))))")
                                .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private func laneRow(_ lane: NightLaneContext) -> some View {
        let selected = lane.selection.wrappedValue.flatMap { date in
            movement.first { abs($0.date.timeIntervalSince(date)) < 60 }
        }
        let value = !loaded || movement.isEmpty ? "—" : selected.map { "\($0.totalMovement)" } ?? "\(movement.count)"
        return NightLane(title: "MOVEMENT", value: value, unit: selected == nil ? "min" : "score", color: Theme.amber,
                         note: comparison == nil ? nil : "Watch", noteColor: Theme.cool, height: lane.height) {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if movement.isEmpty {
                Text(error ?? "No movement recorded for this night").font(.caption).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    marks
                    if let date = lane.selection.wrappedValue { NightLaneSelection(date: date) }
                }
                .nightLane(lane)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The pod's movement through the night, \(movement.count) minutes")
    }

    /// Pod minutes as bars, the Watch's wrist movement as a line over them; each scaled to its own peak.
    @ChartContentBuilder private var marks: some ChartContent {
        let podPeak = WatchMotionComparison.peak(movement.map { Double($0.totalMovement) })
        // A recording can run past the bed record; only the night shown is drawn and scaled.
        let watchPoints = comparison?.watch.filter { $0.date >= record.enteredBedDate && $0.date <= record.leftBedDate } ?? []
        let watchPeak = WatchMotionComparison.peak(watchPoints.map(\.value))
        ForEach(movement) { minute in
            BarMark(x: .value("Time", minute.date, unit: .minute),
                    y: .value("Movement", min(Double(minute.totalMovement) / podPeak, 1.2)))
                .foregroundStyle(Theme.amber.opacity(comparison == nil ? 1 : 0.6))
        }
        // One series per run, so gaps without readings stay gaps.
        ForEach(Array(WatchMotionComparison.runs(watchPoints).enumerated()), id: \.offset) { run, points in
            ForEach(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("Movement", min(point.value / watchPeak, 1.2)),
                         series: .value("Source", "Watch \(run)"))
                    .foregroundStyle(Theme.cool)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
        }
    }

    private var chart: some View {
        Chart { marks }
        .chartXScale(domain: record.enteredBedDate...max(record.enteredBedDate, record.leftBedDate))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.cardBorder)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour()).font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .frame(height: 120)
        .accessibilityLabel("The pod's movement through the night, \(movement.count) minutes")
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption).foregroundStyle(Theme.text2)
        }
    }

    private func load() async {
        loaded = false
        error = nil
        comparison = nil
        do {
            // One night is at most ~900 minutes; the week-wide fetch caps out well short of that across a week.
            movement = try await APIBackend.current.createClient()
                .getMovement(side: side, start: record.enteredBedDate, end: record.leftBedDate)
                .filter { $0.date >= record.enteredBedDate && $0.date <= record.leftBedDate }
                .sorted { $0.date < $1.date }
        } catch {
            movement = []
            self.error = "The pod's movement couldn't be loaded"
        }
        // The Watch is only comparable on the side its wearer sleeps on.
        if side == profile.defaultSide, let recording = watchRecording, let file = try? WatchMotionFile.decode(Data(contentsOf: recording.url)) {
            comparison = WatchMotionComparison.build(file: file, pod: movement)
        }
        loaded = true
    }
}
