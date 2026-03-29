import SwiftUI
import Charts

/// Bed temperature trend chart — fetches historical data from tRPC and
/// shows left, right, and ambient temperature lines with a time range selector.
/// Matches the web core's BED TEMPERATURE TREND card.
struct BedTempTrendView: View {
    @Environment(SettingsManager.self) private var settingsManager
    enum TimeRange: String, CaseIterable {
        case h1 = "1H"
        case h6 = "6H"
        case h12 = "12H"
        case h24 = "24H"

        var seconds: TimeInterval {
            switch self {
            case .h1: return 3600
            case .h6: return 6 * 3600
            case .h12: return 12 * 3600
            case .h24: return 24 * 3600
            }
        }

        var limit: Int {
            switch self {
            case .h1: return 120
            case .h6: return 360
            case .h12: return 720
            case .h24: return 1440
            }
        }
    }

    struct TempPoint: Identifiable {
        let id = UUID()
        let time: Date
        let left: Float?
        let right: Float?
        let ambient: Float?
        let humidity: Float?
    }

    @State private var range: TimeRange = .h6
    @State private var points: [TempPoint] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header + range selector
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.amber)
                    Text("BED TEMPERATURE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(1)
                }
                Spacer()
                HStack(spacing: 0) {
                    ForEach(TimeRange.allCases, id: \.self) { r in
                        Button {
                            range = r
                        } label: {
                            Text(r.rawValue)
                                .font(.system(size: 10, weight: range == r ? .bold : .medium))
                                .foregroundColor(range == r ? .white : Theme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(range == r ? Color.white.opacity(0.12) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            if isLoading && points.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Theme.textMuted)
                    Spacer()
                }
                .frame(height: 120)
            } else if points.isEmpty {
                HStack {
                    Spacer()
                    Text("No temperature data")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
                .frame(height: 120)
            } else {
                // Chart
                Chart {
                    ForEach(points.filter { $0.left != nil }) { p in
                        LineMark(
                            x: .value("Time", p.time),
                            y: .value("°F", p.left!),
                            series: .value("Series", "Left")
                        )
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    ForEach(points.filter { $0.right != nil }) { p in
                        LineMark(
                            x: .value("Time", p.time),
                            y: .value("°F", p.right!),
                            series: .value("Series", "Right")
                        )
                        .foregroundStyle(Color(hex: "40e0d0"))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    ForEach(points.filter { $0.ambient != nil }) { p in
                        LineMark(
                            x: .value("Time", p.time),
                            y: .value("°F", p.ambient!),
                            series: .value("Series", "Ambient")
                        )
                        .foregroundStyle(Theme.amber)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: yDomain)
                .transaction { $0.animation = nil }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Theme.cardBorder)
                        AxisValueLabel()
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(height: 120)

                // Legend
                HStack(spacing: 12) {
                    Spacer()
                    legendDot(color: Theme.amber, label: "Ambient")
                    legendDot(color: Theme.accent, label: "Left")
                    legendDot(color: Color(hex: "40e0d0"), label: "Right")
                    Spacer()
                }

                // Summary stats
                HStack(spacing: 0) {
                    statItem(value: avgLeft, label: "Avg Bed L")
                    statItem(value: avgRight, label: "Avg Bed R")
                    statItem(value: avgAmbient, label: "Avg Ambient")
                    statItem(value: avgHumidity, label: "Humidity", suffix: "%")
                }
            }
        }
        .cardStyle()
        .task(id: range) {
            await fetchData(for: range)
        }
    }

    // MARK: - Computed

    private var yDomain: ClosedRange<Float> {
        let all = points.compactMap(\.left) + points.compactMap(\.right) + points.compactMap(\.ambient)
        guard let lo = all.min(), let hi = all.max() else { return 65...85 }
        let padding: Float = max((hi - lo) * 0.1, 1)
        return (lo - padding)...(hi + padding)
    }

    private var avgLeft: String {
        let vals = points.compactMap(\.left)
        guard !vals.isEmpty else { return "--" }
        return "\(Int(vals.reduce(0, +) / Float(vals.count)))°"
    }

    private var avgRight: String {
        let vals = points.compactMap(\.right)
        guard !vals.isEmpty else { return "--" }
        return "\(Int(vals.reduce(0, +) / Float(vals.count)))°"
    }

    private var avgAmbient: String {
        let vals = points.compactMap(\.ambient)
        guard !vals.isEmpty else { return "--" }
        return "\(Int(vals.reduce(0, +) / Float(vals.count)))°"
    }

    private var avgHumidity: String {
        let vals = points.compactMap(\.humidity)
        guard !vals.isEmpty else { return "--" }
        return "\(Int(vals.reduce(0, +) / Float(vals.count)))"
    }

    // MARK: - Data

    private var apiUnit: String {
        settingsManager.temperatureFormat == .celsius ? "C" : "F"
    }

    private func fetchData(for requestedRange: TimeRange) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let end = Date()
            let start = end.addingTimeInterval(-requestedRange.seconds)
            let readings = try await APIBackend.current.createClient().getBedTempHistory(
                start: start, end: end, limit: requestedRange.limit, unit: apiUnit
            )
            guard !Task.isCancelled, requestedRange == range else { return }
            // tRPC returns descending — reverse for chronological
            points = readings.reversed().compactMap { r in
                guard let date = r.date else { return nil }
                return TempPoint(
                    time: date,
                    left: r.leftF,
                    right: r.rightF,
                    ambient: r.ambientTemp.map { Float($0) },
                    humidity: r.humidity.map { Float($0) }
                )
            }
        } catch {
            // Clear stale data from previous range so chart doesn't show wrong data
            if requestedRange == range {
                points = []
            }
        }
    }

    // MARK: - Subviews

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 8)).foregroundColor(Theme.textMuted)
        }
    }

    private func statItem(value: String, label: String, suffix: String = "") -> some View {
        VStack(spacing: 2) {
            Text(value + suffix)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}
