import SwiftUI
import Charts

// MARK: - Zone

struct Zone {
    let label: String
    let range: ClosedRange<Double>
    let color: Color
}

// MARK: - Vitals Chart Card

struct VitalsChartCard: View {
    let title: String
    let icon: String
    let color: Color
    let unit: String
    let records: [VitalsRecord]
    let valueKey: KeyPath<VitalsRecord, Double?>
    let zones: [Zone]
    let average: Double?

    @State private var selectedDate: Date?

    private var dataPoints: [(Date, Double)] {
        records.compactMap { r in
            r[keyPath: valueKey].map { (r.date, $0) }
        }
    }

    private var selectedRecord: VitalsRecord? {
        guard let date = selectedDate else { return nil }
        return records.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    private var values: [Double] { dataPoints.map(\.1) }
    private var minVal: Double { values.min() ?? 0 }
    private var maxVal: Double { values.max() ?? 0 }
    private var avgVal: Double {
        average ?? (values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(color)
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(1)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    let displayVal = selectedRecord?[keyPath: valueKey] ?? dataPoints.last?.1
                    let displayTime = selectedRecord?.timeLabel

                    Text("\(Int(displayVal ?? 0)) \(unit)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(color)
                    Text(displayTime ?? " ")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
                .frame(width: 70, alignment: .trailing)
            }

            if dataPoints.isEmpty {
                Text("No data available")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    // Zone backgrounds
                    ForEach(zones, id: \.label) { zone in
                        RectangleMark(
                            yStart: .value("Min", zone.range.lowerBound),
                            yEnd: .value("Max", zone.range.upperBound)
                        )
                        .foregroundStyle(zone.color)
                    }

                    // Average line
                    RuleMark(y: .value("Avg", avgVal))
                        .foregroundStyle(color.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .leading) {
                            Text("avg")
                                .font(.system(size: 8))
                                .foregroundColor(color.opacity(0.5))
                        }

                    // Data line — use record ID for stable identity
                    ForEach(records.filter { $0[keyPath: valueKey] != nil }, id: \.id) { record in
                        if let val = record[keyPath: valueKey] {
                            LineMark(
                                x: .value("Time", record.date),
                                y: .value(title, val)
                            )
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            AreaMark(
                                x: .value("Time", record.date),
                                y: .value(title, val)
                            )
                            .foregroundStyle(
                                Theme.cool.opacity(0.12)
                            )
                            .interpolationMethod(.catmullRom)
                        }
                    }

                    // Selection indicator
                    if let sel = selectedRecord, let val = sel[keyPath: valueKey] {
                        PointMark(
                            x: .value("Time", sel.date),
                            y: .value(title, val)
                        )
                        .foregroundStyle(Theme.text1)
                        .symbolSize(60)

                        RuleMark(x: .value("Time", sel.date))
                            .foregroundStyle(Theme.text1.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Theme.cardBorder)
                        AxisValueLabel()
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { _ in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let date: Date = proxy.value(atX: location.x) else { return }
                                Haptics.light()
                                if selectedDate != nil && abs((selectedDate ?? .distantPast).timeIntervalSince(date)) < 60 {
                                    selectedDate = nil
                                } else {
                                    selectedDate = date
                                }
                            }
                    }
                }
                .frame(height: 180)

                // Legend: min / avg / max + zone labels
                HStack(spacing: 16) {
                    legendItem("Min", value: "\(Int(minVal))", color: Theme.textMuted)
                    legendItem("Avg", value: "\(Int(avgVal))", color: color.opacity(0.7))
                    legendItem("Max", value: "\(Int(maxVal))", color: Theme.textMuted)

                    Spacer()

                    // Zone labels
                    ForEach(zones, id: \.label) { zone in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(zone.color.opacity(3))
                                .frame(width: 8, height: 8)
                            Text(zone.label)
                                .font(.system(size: 9))
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private func legendItem(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption2.weight(.medium).monospaced())
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Theme.textMuted)
        }
    }
}
