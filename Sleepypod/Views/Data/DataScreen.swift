import SwiftUI

struct DataScreen: View {
    @Environment(MetricsManager.self) private var metricsManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // WiFi / power header bar
                DataHeaderBar()

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

// MARK: - Data Header Bar

private struct DataHeaderBar: View {
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        HStack {
            // WiFi strength
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                Text("\(deviceManager.deviceStatus?.wifiStrength ?? 0)%")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            // Power indicator
            Image(systemName: "power")
                .font(.caption)
                .foregroundColor(deviceManager.isConnected ? Theme.healthy : Theme.textMuted)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
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
                    Haptics.tap()
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
