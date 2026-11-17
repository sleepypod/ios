import SwiftUI
import Charts

/// Heart rate, HRV and breathing through one night as three stacked rows on a shared time axis, like the web app's
/// vitals chart: the night's middle half as a band, the raw readings faint, and a 9-reading centred mean over them.
/// Dragging across any row shows one crosshair through all three.
struct NightVitalsCard: View {
    let vitals: [VitalsRecord]
    var loading = false
    @State private var selected: Date?

    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private struct Metric: Identifiable {
        let id: String
        let title: String
        let unit: String
        let key: KeyPath<VitalsRecord, Double?>
        let decimals: Int
        let color: Color
    }

    private let metrics: [Metric] = [
        Metric(id: "hr", title: "HR", unit: "bpm", key: \.heartRate, decimals: 0, color: Theme.red),
        Metric(id: "hrv", title: "HRV", unit: "ms", key: \.hrv, decimals: 0, color: Theme.cool),
        Metric(id: "br", title: "BREATH", unit: "br/min", key: \.breathingRate, decimals: 1, color: Theme.green)
    ]

    private var sorted: [VitalsRecord] { vitals.sorted { $0.date < $1.date } }

    /// The reading nearest the crosshair, shared by every row.
    private var selectedRecord: VitalsRecord? {
        guard let selected else { return nil }
        return sorted.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        let records = sorted
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("VITALS")
                Spacer()
                if let record = selectedRecord {
                    Text(record.date, format: .dateTime.hour().minute())
                        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                }
            }
            if loading {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(metric.title, size: 10)
                        LoadingBlock(height: 64)
                    }
                }
            } else if let first = records.first?.date, let last = records.last?.date, last > first {
                ForEach(metrics) { metric in
                    row(metric, records: records, domain: first...last, showsAxis: metric.id == metrics.last?.id)
                }
            } else {
                Text("No vitals recorded for this night")
                    .font(.subheadline).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .cardStyle()
    }

    private func row(_ metric: Metric, records: [VitalsRecord], domain: ClosedRange<Date>, showsAxis: Bool) -> some View {
        let points = records.compactMap { r in r[keyPath: metric.key].map { Point(date: r.date, value: $0) } }
        let values = points.map(\.value).sorted()
        let runs = Self.runs(points)
        let format: (Double) -> String = { String(format: "%.\(metric.decimals)f", $0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(metric.title, size: 10)
                Spacer()
                Group {
                    if let record = selectedRecord {
                        Text("\(record[keyPath: metric.key].map(format) ?? "—") \(metric.unit)")
                    } else if let lo = values.first, let hi = values.last {
                        Text("avg \(format(values.reduce(0, +) / Double(values.count))) · \(format(lo))–\(format(hi)) \(metric.unit)")
                    }
                }
                .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
            }
            if points.count < 2 {
                Text("No readings")
                    .font(.caption).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                let lo = values.first ?? 0, hi = values.last ?? 0
                let pad = max((hi - lo) * 0.15, 1)
                Chart {
                    RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("End", domain.upperBound),
                                  yStart: .value("P25", Self.percentile(values, 0.25)),
                                  yEnd: .value("P75", Self.percentile(values, 0.75)))
                        .foregroundStyle(metric.color.opacity(0.1))
                    // One series per run, so gaps without readings stay gaps.
                    ForEach(Array(runs.enumerated()), id: \.offset) { run, points in
                        ForEach(points) { point in
                            LineMark(x: .value("Time", point.date), y: .value(metric.title, point.value),
                                     series: .value("Series", "raw \(run)"))
                                .foregroundStyle(metric.color.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                        }
                        ForEach(Self.centredMean(points)) { point in
                            LineMark(x: .value("Time", point.date), y: .value(metric.title, point.value),
                                     series: .value("Series", "mean \(run)"))
                                .foregroundStyle(metric.color)
                                .lineStyle(StrokeStyle(lineWidth: 1.6))
                        }
                    }
                    if let record = selectedRecord {
                        RuleMark(x: .value("Selected", record.date))
                            .foregroundStyle(Theme.text3)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: (lo - pad)...(hi + pad))
                .chartYAxis(.hidden)
                .chartXAxis {
                    if showsAxis {
                        AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.cardBorder)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.hour()).font(.caption2).foregroundStyle(Theme.textMuted)
                                }
                            }
                        }
                    } else {
                        AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.cardBorder)
                        }
                    }
                }
                .chartXSelection(value: $selected)
                .frame(height: showsAxis ? 84 : 64)
                .accessibilityLabel("\(metric.title) through the night")
                .accessibilityValue(values.isEmpty ? "" : "\(format(lo)) to \(format(hi)) \(metric.unit)")
            }
        }
    }

    /// Splits readings wherever more than `maxGap` passes without one.
    static func runs(_ points: [Point], maxGap: TimeInterval = 600) -> [[Point]] {
        var runs: [[Point]] = []
        for point in points {
            if let last = runs.last?.last, point.date.timeIntervalSince(last.date) <= maxGap {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        return runs
    }

    /// The mean of each reading and the four either side of it within the run; ends use what they have.
    static func centredMean(_ points: [Point], window: Int = 9) -> [Point] {
        let half = window / 2
        return points.indices.map { i in
            let slice = points[max(0, i - half)...min(points.count - 1, i + half)]
            return Point(date: points[i].date, value: slice.reduce(0) { $0 + $1.value } / Double(slice.count))
        }
    }

    /// Linear-interpolated percentile of already sorted values.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let rank = p * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down)), upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
    }
}
