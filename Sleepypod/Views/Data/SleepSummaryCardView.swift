import SwiftUI

struct SleepSummaryCardView: View {
    @Environment(MetricsManager.self) private var metricsManager

    private var record: SleepRecord? {
        metricsManager.selectedDayRecord
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SLEEP SUMMARY")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
                Spacer()
                if let avgHours = formattedAverage {
                    Text("Avg: \(avgHours)")
                        .font(.caption)
                        .foregroundColor(Theme.healthy)
                }
            }

            if let record {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    summaryItem(icon: "moon.fill", iconColor: Theme.purple,
                                value: record.bedtimeFormatted, label: "Bedtime")
                    summaryItem(icon: "sun.max.fill", iconColor: Theme.amber,
                                value: record.wakeTimeFormatted, label: "Wake Time")
                    summaryItem(icon: "clock.fill", iconColor: Theme.textSecondary,
                                value: record.durationFormatted, label: "Duration")
                    summaryItem(icon: "bed.double.fill", iconColor: Theme.textSecondary,
                                value: "\(record.timesExitedBed)", label: "Exits")
                }
            } else {
                Text("No data for selected period")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .cardStyle()
    }

    private var formattedAverage: String? {
        let avg = metricsManager.averageSleepHours
        guard avg > 0 else { return nil }
        let hours = Int(avg)
        let minutes = Int((avg - Double(hours)) * 60)
        return "\(hours)h \(minutes)m"
    }

    private func summaryItem(icon: String, iconColor: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
