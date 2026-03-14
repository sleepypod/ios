import SwiftUI

struct SideSelectorView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        HStack(spacing: 0) {
            // Left button
            sideButton(side: .left) {
                deviceManager.selectSide(.left)
            }

            // Link button (center between sides)
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
        let status = deviceManager.deviceStatus?.status(for: side)
        let sideOffset = status.map { TemperatureConversion.tempFToOffset($0.targetTemperatureF) } ?? 0
        let sideTempF = status?.currentTemperatureF ?? 80
        let sideIsOn = status?.isOn ?? false

        return Button { Haptics.tap(); action() } label: {
            VStack(spacing: 4) {
                // Top row: name + presence dot
                HStack(spacing: 6) {
                    Text("\(side.displayName) Side")
                        .font(.subheadline.weight(.medium))

                    if sideIsOn {
                        Circle()
                            .fill(Theme.healthy)
                            .frame(width: 6, height: 6)
                    }
                }

                // Detail row: trend icon + offset + temp
                if sideIsOn {
                    HStack(spacing: 4) {
                        // Trend icon
                        Image(systemName: trendIcon(for: sideOffset))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TempColor.forOffset(sideOffset))

                        Text("\(TemperatureConversion.offsetDisplay(sideOffset)) \u{00B7} \(TemperatureConversion.displayTemp(sideTempF, format: settingsManager.temperatureFormat))")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
            .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color(hex: "1e2a3a") : Color.clear
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

    /// Returns SF Symbol name for trend direction
    private func trendIcon(for offset: Int) -> String {
        if offset > 0 { return "arrow.upper.right" }
        if offset < 0 { return "arrow.lower.right" }
        return "equal"
    }
}
