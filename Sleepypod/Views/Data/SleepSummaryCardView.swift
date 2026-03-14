import SwiftUI

struct SleepSummaryCardView: View {
    @Environment(MetricsManager.self) private var metricsManager

    private var record: SleepRecord? {
        metricsManager.selectedDayRecord
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: "Sleep Summary" with date and trend
            HStack {
                Text("Sleep Summary")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                if let record {
                    Text(record.enteredBedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Text("\u{2197} 5%")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Theme.healthy)
            }

            if let record {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    summaryItem(value: record.bedtimeFormatted, label: "BEDTIME")
                    summaryItem(value: record.wakeTimeFormatted, label: "WAKE TIME")
                    summaryItem(value: record.durationFormatted, label: "DURATION")
                    summaryItem(value: "\(record.timesExitedBed) time\(record.timesExitedBed == 1 ? "" : "s")", label: "EXITS")
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

    private func summaryItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(Theme.textSecondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
