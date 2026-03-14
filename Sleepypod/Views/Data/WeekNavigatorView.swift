import SwiftUI

struct WeekNavigatorView: View {
    @Environment(MetricsManager.self) private var metricsManager

    var body: some View {
        HStack {
            Button {
                Haptics.light()
                metricsManager.previousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(metricsManager.weekLabel)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)

            Spacer()

            Button {
                Haptics.light()
                metricsManager.nextWeek()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
}
