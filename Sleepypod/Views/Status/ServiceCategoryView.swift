import SwiftUI

struct ServiceCategoryView: View {
    let category: ServiceCategory
    var onRetry: ((StatusInfo) -> Void)?
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: category.iconName)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: category.iconColorHex))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: category.iconColorHex).opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text(category.description)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                        if let subtitle = category.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundColor(Theme.accent)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Status badge
                    HStack(spacing: 4) {
                        let allHealthy = category.healthyCount == category.services.count
                        Image(systemName: allHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(allHealthy ? Theme.healthy : Theme.amber)
                        Text("\(category.healthyCount)/\(category.services.count)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "222222"))
                    .clipShape(Capsule())

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()
                    .background(Theme.cardBorder)
                    .padding(.vertical, 8)

                VStack(spacing: 8) {
                    ForEach(category.services) { service in
                        ServiceRowView(service: service) {
                            onRetry?(service)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
