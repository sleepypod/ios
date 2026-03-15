import SwiftUI

struct ServiceRowView: View {
    let service: StatusInfo
    var onRetry: (() -> Void)?

    private var statusColor: Color {
        switch service.status {
        case .healthy, .started:
            Theme.healthy
        case .failed:
            Theme.error
        case .restarting, .retrying:
            Theme.amber
        case .notStarted:
            Theme.textMuted
        }
    }

    private var statusIcon: String {
        switch service.status {
        case .healthy, .started:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.circle.fill"
        case .restarting, .retrying:
            "exclamationmark.triangle.fill"
        case .notStarted:
            "minus.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.subheadline)
                    .foregroundColor(.white)
                if !service.description.isEmpty {
                    Text(service.description)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                if !service.message.isEmpty && service.message != service.description {
                    Text(service.message)
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Retry button for failed services
            if service.status == .failed, let onRetry {
                Button {
                    Haptics.medium()
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Status icon
            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundColor(statusColor)
        }
        .padding(.vertical, 4)
    }
}
