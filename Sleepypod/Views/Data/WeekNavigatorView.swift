import SwiftUI

struct WeekNavigatorView: View {
    @Environment(MetricsManager.self) private var metricsManager

    var body: some View {
        HStack(spacing: 6) {
            // Previous week
            Button {
                Haptics.light()
                metricsManager.previousWeek()
                Task { await metricsManager.fetchAll() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 32, height: 36)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Week label
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent)
                Text(metricsManager.weekLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Next week (disabled if current week)
            Button {
                Haptics.light()
                metricsManager.nextWeek()
                Task { await metricsManager.fetchAll() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isCurrentWeek ? Theme.textMuted.opacity(0.3) : Theme.textSecondary)
                    .frame(width: 32, height: 36)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isCurrentWeek)
        }
    }

    private var isCurrentWeek: Bool {
        let now = Date()
        let currentWeekStart = Calendar.current.startOfWeek(for: now)
        return metricsManager.selectedWeekStart >= currentWeekStart
    }
}
