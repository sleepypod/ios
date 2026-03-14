import SwiftUI
import Charts

struct WeeklyBarChartView: View {
    @Environment(MetricsManager.self) private var metricsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SLEEP TIMELINE")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            if metricsManager.sleepRecords.isEmpty {
                Text("No sleep data for this week")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(metricsManager.sleepRecords) { record in
                    BarMark(
                        x: .value("Day", record.dayLabel),
                        y: .value("Hours", record.durationHours)
                    )
                    .foregroundStyle(Theme.cyan)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Theme.cardBorder)
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let day = value.as(String.self) {
                                Text(day)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .cardStyle()
    }
}
