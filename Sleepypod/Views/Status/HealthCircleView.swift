import SwiftUI

struct HealthCircleView: View {
    @Environment(StatusManager.self) private var statusManager

    private let circleSize: CGFloat = 180
    private let lineWidth: CGFloat = 8

    private var progress: Double {
        statusManager.healthProgress
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color(hex: "222222"), lineWidth: lineWidth)
                    .frame(width: circleSize, height: circleSize)

                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.healthy, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: circleSize, height: circleSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                // Center label
                VStack(spacing: 4) {
                    Text("\(statusManager.healthyCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("OF \(statusManager.totalCount) HEALTHY")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(0.5)
                }
            }

            // Legend
            HStack(spacing: 20) {
                legendItem(color: Theme.healthy, label: "\(statusManager.healthyCount) Running")
                legendItem(color: Theme.textMuted, label: "\(statusManager.totalCount - statusManager.healthyCount) Stopped")
            }
        }
        .cardStyle()
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }
}
