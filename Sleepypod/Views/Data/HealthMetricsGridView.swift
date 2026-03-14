import SwiftUI

struct HealthMetricsGridView: View {
    @Environment(MetricsManager.self) private var metricsManager

    private var summary: VitalsSummary? {
        metricsManager.vitalsSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with heart icon
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(Theme.error)
                Text("HEALTH METRICS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }

            if let summary {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    metricCard(icon: "heart.fill", iconColor: Theme.error,
                               value: formatValue(summary.avgHeartRate), unit: "bpm", label: "Avg HR")
                    metricCard(icon: "waveform.path.ecg", iconColor: Theme.healthy,
                               value: formatValue(summary.avgHRV), unit: "ms", label: "HRV")
                    metricCard(icon: "wind", iconColor: Theme.cyan,
                               value: formatValue(summary.avgBreathingRate), unit: "brpm", label: "Breath")
                    metricCard(icon: "arrow.down.heart.fill", iconColor: Theme.cooling,
                               value: formatValue(summary.minHeartRate), unit: "bpm", label: "Min HR")
                    metricCard(icon: "arrow.up.heart.fill", iconColor: Theme.warming,
                               value: formatValue(summary.maxHeartRate), unit: "bpm", label: "Max HR")
                    metricCard(icon: "o2.circle.fill", iconColor: Theme.purple,
                               value: "—", unit: "%", label: "SpO2")
                }
            } else {
                Text("No vitals data available")
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .cardStyle()
    }

    private func metricCard(icon: String, iconColor: Color, value: String, unit: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.2))
                .clipShape(Circle())

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f", value)
    }
}
