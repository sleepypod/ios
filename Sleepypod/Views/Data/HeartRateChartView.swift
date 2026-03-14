import SwiftUI
import Charts

struct HeartRateChartView: View {
    @Environment(MetricsManager.self) private var metricsManager

    private var vitals: [VitalsRecord] {
        metricsManager.vitalsRecords.filter { $0.heartRate != nil }
    }

    private var avgHR: Double? {
        metricsManager.vitalsSummary?.avgHeartRate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with heart icon and avg on right
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(Theme.error)
                    Text("HEART RATE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(1)
                }
                Spacer()
                if let avg = avgHR {
                    Text("Avg: \(Int(avg)) bpm")
                        .font(.caption)
                        .foregroundColor(Theme.error)
                }
            }

            if vitals.isEmpty {
                Text("No heart rate data available")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(vitals) { vital in
                    LineMark(
                        x: .value("Time", vital.date),
                        y: .value("HR", vital.heartRate ?? 0)
                    )
                    .foregroundStyle(Theme.error)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    if let avg = avgHR {
                        RuleMark(y: .value("Average", avg))
                            .foregroundStyle(Theme.error.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Theme.cardBorder)
                        AxisValueLabel {
                            if let hr = value.as(Double.self) {
                                Text("\(Int(hr))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
                .frame(height: 160)

                // Info banner
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                    Text("Heart rate data validated with 6 participants across multiple sleep sessions")
                        .font(.caption2)
                        .foregroundColor(Theme.accent.opacity(0.9))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cooling.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .cardStyle()
    }
}
