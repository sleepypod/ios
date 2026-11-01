import SwiftUI
import Charts

/// The pod's per-minute movement score across one night, with the Watch's wrist movement drawn over it when a
/// Watch recording covers the same night.
struct PodMovementCardView: View {
    let record: SleepRecord
    let side: Side
    @Environment(WatchMotionReceiver.self) private var watchMotion
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
        .task(id: record.id) { await load() }
    }

    private var chart: some View {
        let podPeak = WatchMotionComparison.peak(movement.map { Double($0.totalMovement) })
        let watchPeak = comparison?.watchPeak ?? 1
        return Chart {
            ForEach(movement) { minute in
                BarMark(x: .value("Time", minute.date, unit: .minute),
                        y: .value("Movement", min(Double(minute.totalMovement) / podPeak, 1.2)))
                    .foregroundStyle(Theme.amber.opacity(comparison == nil ? 1 : 0.6))
            }
            if let comparison {
                ForEach(comparison.watch) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Movement", min(point.value / watchPeak, 1.2)),
                             series: .value("Source", "Watch"))
                        .foregroundStyle(Theme.cool)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
        }
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
        if let recording = watchRecording, let file = try? WatchMotionFile.decode(Data(contentsOf: recording.url)) {
            comparison = WatchMotionComparison.build(file: file, pod: movement)
        }
        loaded = true
    }
}
