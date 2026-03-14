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

    private var restlessMinutes: Int {
        // Estimate restless minutes from total movement
        min(totalMovement, 60)
    }

    private var timeStillPercent: Int {
        guard let record = metricsManager.selectedDayRecord else { return 0 }
        let totalSeconds = record.sleepPeriodSeconds
        guard totalSeconds > 0 else { return 0 }
        let restlessSeconds = restlessMinutes * 60
        let stillPercent = max(0, 100 - (restlessSeconds * 100 / totalSeconds))
        return stillPercent
    }

    private var restlessnessLevel: String {
        if restlessMinutes < 15 { return "Low" }
        if restlessMinutes < 30 { return "Medium" }
        return "High"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and restless info
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                        .foregroundColor(Theme.amber)
                    Text("MOVEMENT")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(1)
                }
                Spacer()
                Text("Restless: \(restlessMinutes) min")
                    .font(.caption)
                    .foregroundColor(Theme.amber)
            }

            // Three stats in a row
            HStack(spacing: 0) {
                statItem(value: "\(movements.count)", label: "Position Changes")
                Divider().frame(height: 30).background(Theme.cardBorder)
                statItem(value: "\(timeStillPercent)%", label: "Time Still")
                Divider().frame(height: 30).background(Theme.cardBorder)
                statItem(value: restlessnessLevel, label: "Restlessness")
            }
            .padding(.bottom, 4)

            // Movement bar chart
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
