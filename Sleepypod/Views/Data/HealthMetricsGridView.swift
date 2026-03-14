import SwiftUI

struct HealthMetricsGridView: View {
    @Environment(MetricsManager.self) private var metricsManager

    private var summary: VitalsSummary? {
        metricsManager.vitalsSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HEALTH METRICS")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            if let summary {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricItem(icon: "heart.fill", iconColor: Theme.error,
                               value: formatValue(summary.avgHeartRate), unit: "bpm", label: "Avg HR")
                    metricItem(icon: "waveform.path.ecg", iconColor: Color(hex: "50b4dc"),
                               value: formatValue(summary.avgHRV), unit: "ms", label: "HRV")
                    metricItem(icon: "wind", iconColor: Theme.cyan,
                               value: formatValue(summary.avgBreathingRate), unit: "brpm", label: "Breath")
                    metricItem(icon: "arrow.down.heart.fill", iconColor: Theme.cooling,
                               value: formatValue(summary.minHeartRate), unit: "bpm", label: "Min HR")
                    metricItem(icon: "arrow.up.heart.fill", iconColor: Theme.warming,
                               value: formatValue(summary.maxHeartRate), unit: "bpm", label: "Max HR")
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

    private func metricItem(icon: String, iconColor: Color, value: String, unit: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func formatValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f", value)
    }
}
