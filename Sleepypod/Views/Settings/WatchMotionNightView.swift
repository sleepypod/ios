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
                Text("Wrist movement from the Watch and the pod's movement score for \(settings.sideName(for: profile.defaultSide)), each scaled to its own night. Peaks that line up are movements both sensors caught.")
                    .font(.footnote).foregroundStyle(Theme.text2).lineSpacing(3)
                    .padding(.horizontal, 8)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 8)
                }
                if let comparison {
                    chart(comparison).cardStyle()
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

    private func chart(_ comparison: WatchMotionComparison) -> some View {
        let watchPeak = comparison.watchPeak, podPeak = comparison.podPeak
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                legend("Watch", color: Theme.cool)
                legend("Pod", color: Theme.amber)
            }
            Chart {
                ForEach(comparison.pod) { point in
                    BarMark(x: .value("Time", point.date, unit: .minute), y: .value("Movement", min(point.value / podPeak, 1.2)))
                        .foregroundStyle(Theme.amber.opacity(0.6))
                }
                ForEach(comparison.watch) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Movement", min(point.value / watchPeak, 1.2)),
                             series: .value("Source", "Watch"))
                        .foregroundStyle(Theme.cool)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                        .interpolationMethod(.linear)
                }
            }
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
            .frame(height: 200)
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption).foregroundStyle(Theme.text2)
        }
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
