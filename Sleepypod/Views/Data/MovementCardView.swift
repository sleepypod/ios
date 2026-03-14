import SwiftUI
import Charts

struct MovementCardView: View {
    @Environment(MetricsManager.self) private var metricsManager

    private var movements: [MovementRecord] {
        metricsManager.movementRecords
    }

    private var totalMovement: Int {
        metricsManager.totalMovement
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MOVEMENT")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            // Stats row
            HStack(spacing: 0) {
                statItem(value: "\(movements.count)", label: "Position Changes")
                Divider().frame(height: 30).background(Theme.cardBorder)
                statItem(value: "\(totalMovement)", label: "Total Movement")
            }
            .padding(.bottom, 4)

            // Movement chart
            if movements.isEmpty {
                Text("No movement data available")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(movements) { record in
                    BarMark(
                        x: .value("Time", record.date),
                        y: .value("Movement", record.totalMovement)
                    )
                    .foregroundStyle(Theme.amber)
                    .cornerRadius(2)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Theme.cardBorder)
                        AxisValueLabel {
                            if let val = value.as(Int.self) {
                                Text("\(val)")
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
                .frame(height: 120)
            }
        }
        .cardStyle()
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
