import SwiftUI

struct HealthCircleView: View {
    @Environment(StatusManager.self) private var statusManager

    private var progress: Double {
        statusManager.healthProgress
    }

    var body: some View {
        VStack(spacing: 12) {
            // Compact header with count
            HStack(spacing: 12) {
                // Mini ring
                ZStack {
                    Circle()
                        .stroke(Color(hex: "222222"), lineWidth: 4)
                        .frame(width: 44, height: 44)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.healthy, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: progress)

                    Text("\(statusManager.healthyCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(statusManager.healthyCount) of \(statusManager.totalCount) Healthy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: "222222"))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.healthy)
                                .frame(width: geo.size.width * progress, height: 6)
                                .animation(.easeInOut(duration: 0.5), value: progress)
                        }
                    }
                    .frame(height: 6)
                }

                Spacer()

                // Legend dots
                VStack(alignment: .trailing, spacing: 4) {
                    legendItem(color: Theme.healthy, label: "\(statusManager.healthyCount) Running")
                    legendItem(color: Theme.textMuted, label: "\(statusManager.totalCount - statusManager.healthyCount) Stopped")
                }
            }
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
}
