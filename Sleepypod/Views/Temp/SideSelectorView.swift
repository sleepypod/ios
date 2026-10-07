import SwiftUI

/// Compact side picker for the Temp toolbar: `Left | link | Right`.
/// Linking highlights both sides and routes changes to both.
struct SideSelectorView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    private let height: CGFloat = 36

    var body: some View {
        let isLinked = deviceManager.isLinked

        HStack(spacing: 2) {
            sideButton(side: .left)
            linkButton
            sideButton(side: .right)
        }
        .padding(3)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isLinked ? Theme.cooling.opacity(0.4) : Theme.cardBorder, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isLinked)
        .animation(.easeInOut(duration: 0.2), value: deviceManager.selectedSide)
        .accessibilityIdentifier("podSideSelector")
    }

    private func sideButton(side: Side) -> some View {
        let isSelected = deviceManager.selectedSide == (side == .left ? .left : .right) ||
                         deviceManager.selectedSide == .both
        let status = deviceManager.deviceStatus?.status(for: side)
        let sideIsOn = status?.isOn ?? false

        return Button {
            Haptics.tap()
            deviceManager.selectSide(side == .left ? .left : .right)
        } label: {
            HStack(spacing: 5) {
                Text(settingsManager.sideName(for: side))
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                if sideIsOn {
                    Circle()
                        .fill(Theme.healthy)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: height - 6)
            .background(isSelected ? Color(hex: "1e2a3a").opacity(0.9) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(side.displayName) side")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var linkButton: some View {
        Button {
            Haptics.medium()
            deviceManager.toggleLink()
        } label: {
            Image(systemName: deviceManager.isLinked ? "link" : "link.badge.plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(deviceManager.isLinked ? .white : Theme.textTertiary)
                .frame(width: height - 6, height: height - 6)
                .background(deviceManager.isLinked ? Theme.cooling : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(deviceManager.isLinked ? "Unlink sides" : "Link sides")
    }
}
