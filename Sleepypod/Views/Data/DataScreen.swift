import SwiftUI

struct DataScreen: View {
    @Environment(MetricsManager.self) private var metricsManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Week navigator
                WeekNavigatorView()

                // Side selector
                DataSideSelectorView()

                if metricsManager.isLoading && metricsManager.sleepRecords.isEmpty {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(40)
                } else {
                    // Weekly bar chart
                    WeeklyBarChartView()

                    // Sleep summary
                    SleepSummaryCardView()

                    // Health metrics grid
                    HealthMetricsGridView()

                    // Heart rate chart
                    HeartRateChartView()

                    // Sleep stages timeline
                    SleepStagesTimelineView()

                    // Movement card
                    MovementCardView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .task {
            await metricsManager.fetchAll()
        }
    }
}

// MARK: - Data Side Selector

private struct DataSideSelectorView: View {
    @Environment(MetricsManager.self) private var metricsManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Side.allCases) { side in
                let isSelected = metricsManager.selectedSide == side
                Button {
                    metricsManager.selectedSide = side
                    Task { await metricsManager.fetchAll() }
                } label: {
                    Text(side.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color(hex: "1e2a3a") : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
