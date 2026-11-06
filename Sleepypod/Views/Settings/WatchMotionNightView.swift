import SwiftUI
import Charts

/// One Watch recording drawn over the pod's movement score for this iPhone's side, so the two sensors can be
/// checked against each other night by night.
struct WatchMotionNightView: View {
    let recording: WatchMotionInbox.Recording
    @Environment(UserProfile.self) private var profile
    @Environment(SettingsManager.self) private var settings
    @State private var comparison: WatchMotionComparison?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Wrist movement from the Watch above the line and the pod's movement score for \(settings.sideName(for: profile.defaultSide)) below it, in 5-minute bars, each scaled to its own night. Bars that meet at the line are movements both sensors caught.")
                    .font(.footnote).foregroundStyle(Theme.text2).lineSpacing(3)
                    .padding(.horizontal, 8)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 8)
                }
                if let comparison {
                    WatchMotionChart(comparison: comparison).cardStyle()
                    GroupedSection("AGREEMENT") {
                        GroupedCard {
                            SettingsRow("Correlation", subtitle: "Per minute, 1 is perfect agreement", height: 56) {
                                RowValue(comparison.correlation.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—", mono: true)
                            }
                            SettingsRow("Minutes compared") { RowValue("\(comparison.pairs.count)", mono: true) }
                            SettingsRow("Watch minutes") { RowValue("\(comparison.watch.count)", mono: true) }
                            SettingsRow("Pod minutes") { RowValue("\(comparison.pod.count)", mono: true) }
                        }
                    }
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(recording.from.formatted(date: .abbreviated, time: .omitted))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: recording.url) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share recording")
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let file = try WatchMotionFile.decode(Data(contentsOf: recording.url))
            let pod: [MovementRecord]
            do {
                pod = try await APIBackend.current.createClient()
                    .getMovement(side: profile.defaultSide, start: recording.from, end: recording.to.addingTimeInterval(60))
            } catch {
                pod = []
                self.error = "The pod's movement couldn't be loaded: \(error.localizedDescription)"
            }
            comparison = WatchMotionComparison.build(file: file, pod: pod)
        } catch {
            self.error = "This recording couldn't be read: \(error.localizedDescription)"
        }
    }
}

/// Watch movement above the line and the pod's below it, in the same time buckets, so a movement both sensors caught
/// reads as two bars meeting at the line. Each is scaled to its own night.
struct WatchMotionChart: View {
    let comparison: WatchMotionComparison
    /// The x-axis, when the chart shows a night rather than the whole recording.
    var domain: ClosedRange<Date>?
    var height: CGFloat = 200

    var body: some View {
        let watch = comparison.watchBuckets, pod = comparison.podBuckets
        let watchPeak = WatchMotionComparison.peak(watch.map(\.value)), podPeak = WatchMotionComparison.peak(pod.map(\.value))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                legend("Watch", color: Theme.cool)
                legend("Pod", color: Theme.amber)
            }
            Chart {
                ForEach(watch) { point in
                    RectangleMark(xStart: .value("Start", point.date), xEnd: .value("End", barEnd(point)),
                                  yStart: .value("Base", 0), yEnd: .value("Movement", min(point.value / watchPeak, 1.2)))
                        .foregroundStyle(Theme.cool)
                }
                ForEach(pod) { point in
                    RectangleMark(xStart: .value("Start", point.date), xEnd: .value("End", barEnd(point)),
                                  yStart: .value("Base", 0), yEnd: .value("Movement", -min(point.value / podPeak, 1.2)))
                        .foregroundStyle(Theme.amber)
                }
                RuleMark(y: .value("Base", 0)).foregroundStyle(Theme.cardBorder).lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartXScale(domain: domain ?? comparison.span)
            .chartYScale(domain: -1.2...1.2)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.cardBorder)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour()).font(.caption2).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .frame(height: height)
            .accessibilityLabel("Watch movement above the line and the pod's below it, in 5-minute bars")
        }
    }

    /// Short of the next bar, so neighbours stay apart.
    private func barEnd(_ point: WatchMotionComparison.Point) -> Date {
        point.date.addingTimeInterval(WatchMotionComparison.bucketSeconds - 40)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption).foregroundStyle(Theme.text2)
        }
    }
}
