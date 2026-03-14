import SwiftUI

struct ServiceRowView: View {
    let service: StatusInfo

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

            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
}
