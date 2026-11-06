import SwiftUI
import Charts

/// The pod's per-minute movement score across one night, or the pod set against the Watch's wrist movement when a
/// Watch recording covers the same night.
struct PodMovementCardView: View {
    let record: SleepRecord
    let side: Side
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow("MOVEMENT")
                Spacer()
                if let r = comparison?.correlation {
                    Text("r \(r.formatted(.number.precision(.fractionLength(2))))")
                        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                } else if loaded && !movement.isEmpty {
                    Text("\(movement.count) min").font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                }
            }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if movement.isEmpty {
                Text(error ?? "No movement recorded for this night")
                    .font(.subheadline).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let comparison {
                WatchMotionChart(comparison: comparison, domain: nightSpan, height: 140)
            } else {
                chart
            }
        }
        .cardStyle()
        .task(id: "\(record.id)-\(side.rawValue)-\(watchMotion.recordings.count)") { await load() }
    }

    private var nightSpan: ClosedRange<Date> { record.enteredBedDate...max(record.enteredBedDate, record.leftBedDate) }

    private var chart: some View {
        let podPeak = WatchMotionComparison.peak(movement.map { Double($0.totalMovement) })
        return Chart {
            ForEach(movement) { minute in
                BarMark(x: .value("Time", minute.date, unit: .minute),
                        y: .value("Movement", min(Double(minute.totalMovement) / podPeak, 1.2)))
                    .foregroundStyle(Theme.amber)
            }
        }
        .chartXScale(domain: nightSpan)
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
