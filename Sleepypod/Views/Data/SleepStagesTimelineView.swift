import SwiftUI
import Charts

struct SleepStagesTimelineView: View {
    @Environment(MetricsManager.self) private var metricsManager

    // Derive presence/absence timeline from sleep records
    private var timelineEntries: [TimelineEntry] {
        guard let record = metricsManager.selectedDayRecord else { return [] }
        return parsePresenceIntervals(record)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SLEEP TIMELINE")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            if timelineEntries.isEmpty {
                Text("No sleep stage data available")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(timelineEntries) { entry in
                    RectangleMark(
                        xStart: .value("Start", entry.startDate),
                        xEnd: .value("End", entry.endDate),
                        y: .value("State", entry.state)
                    )
                    .foregroundStyle(entry.color)
                    .cornerRadius(2)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let state = value.as(String.self) {
                                Text(state)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
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

            // Legend
            HStack(spacing: 16) {
                legendItem(color: Theme.purple, label: "In Bed")
                legendItem(color: Theme.textMuted, label: "Out of Bed")
            }
            .padding(.top, 4)
        }
        .cardStyle()
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func parsePresenceIntervals(_ record: SleepRecord) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []

        // Parse present intervals from JSON string
        if let data = record.presentIntervals.data(using: .utf8),
           let intervals = try? JSONDecoder().decode([[Int]].self, from: data) {
            for interval in intervals {
                guard interval.count >= 2 else { continue }
                let start = Date(timeIntervalSince1970: TimeInterval(interval[0]))
                let end = Date(timeIntervalSince1970: TimeInterval(interval[1]))
                entries.append(TimelineEntry(startDate: start, endDate: end, state: "In Bed", color: Theme.purple))
            }
        }

        // Parse not-present intervals
        if let data = record.notPresentIntervals.data(using: .utf8),
           let intervals = try? JSONDecoder().decode([[Int]].self, from: data) {
            for interval in intervals {
                guard interval.count >= 2 else { continue }
                let start = Date(timeIntervalSince1970: TimeInterval(interval[0]))
                let end = Date(timeIntervalSince1970: TimeInterval(interval[1]))
                entries.append(TimelineEntry(startDate: start, endDate: end, state: "Out of Bed", color: Theme.textMuted))
            }
        }

        return entries.sorted { $0.startDate < $1.startDate }
    }
}

struct TimelineEntry: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let state: String
    let color: Color
}
