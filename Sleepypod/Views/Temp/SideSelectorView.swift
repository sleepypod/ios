import SwiftUI

struct SideSelectorView: View {
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        HStack(spacing: 0) {
            // Left button
            sideButton(side: .left) {
                deviceManager.selectSide(.left)
            }

            // Link button (floating between the two sides)
            linkButton

            // Right button
            sideButton(side: .right) {
                deviceManager.selectSide(.right)
            }
        }
        .padding(6)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sideButton(side: Side, action: @escaping () -> Void) -> some View {
        let isSelected = deviceManager.selectedSide == (side == .left ? .left : .right) ||
                         deviceManager.selectedSide == .both

        return Button { Haptics.tap(); action() } label: {
            HStack(spacing: 8) {
                Text(side.displayName)
                    .font(.subheadline.weight(.medium))

                // Presence indicator
                if let status = deviceManager.deviceStatus?.status(for: side),
                   status.isOn {
                    Circle()
                        .fill(Theme.healthy)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected ?
                    Color(hex: "1e2a3a") : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.cooling.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var linkButton: some View {
        Button {
            Haptics.medium()
            deviceManager.toggleLink()
        } label: {
            Image(systemName: deviceManager.isLinked ? "link" : "link.badge.plus")
                .font(.system(size: 14))
                .foregroundColor(deviceManager.isLinked ? .white : Theme.textTertiary)
                .frame(width: 36, height: 36)
                .background(
                    deviceManager.isLinked ? Theme.cooling : Theme.cardElevated
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(deviceManager.isLinked ? Theme.accent : Theme.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
