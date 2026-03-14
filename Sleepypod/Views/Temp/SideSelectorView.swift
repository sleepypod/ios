import SwiftUI

struct SideSelectorView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        HStack(spacing: 0) {
            sideButton(side: .left)
            Spacer().frame(width: 48) // reserve space under the floating link
            sideButton(side: .right)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            linkButton
        }
    }

    private func sideButton(side: Side) -> some View {
        let isSelected = deviceManager.selectedSide == (side == .left ? .left : .right) ||
                         deviceManager.selectedSide == .both
        let status = deviceManager.deviceStatus?.status(for: side)
        let sideIsOn = status?.isOn ?? false
        let targetTempF = status?.targetTemperatureF ?? 80
        let currentTempF = status?.currentTemperatureF ?? 80
        let sideOffset = TemperatureConversion.tempFToOffset(targetTempF)
        let isWarming = targetTempF > currentTempF
        let isCooling = targetTempF < currentTempF

        return Button {
            Haptics.tap()
            deviceManager.selectSide(side == .left ? .left : .right)
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(side.displayName) Side")
                        .font(.subheadline.weight(.medium))

                    if sideIsOn {
                        Circle()
                            .fill(Theme.healthy)
                            .frame(width: 6, height: 6)
                            .modifier(PulseModifier())
                    }
                }

                HStack(spacing: 4) {
                    if sideIsOn {
                        Image(systemName: trendIcon(warming: isWarming, cooling: isCooling))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TempColor.forOffset(sideOffset))

                        Text("\(TemperatureConversion.offsetDisplay(sideOffset)) \u{00B7} \(TemperatureConversion.displayTemp(currentTempF, format: settingsManager.temperatureFormat))")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                    } else {
                        Image(systemName: "poweroff")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textMuted)

                        Text("Off")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }
            .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color(hex: "1e2a3a").opacity(0.8) : Color.clear
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
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(deviceManager.isLinked ? .white : Theme.textTertiary)
                .frame(width: 46, height: 46)
                .background(
                    deviceManager.isLinked ? Theme.cooling : Color(hex: "1a1a1a")
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color(hex: "0a0a0a"), lineWidth: 3) // dark ring to separate from bar
                )
                .overlay(
                    Circle()
                        .stroke(deviceManager.isLinked ? Theme.accent.opacity(0.5) : Color(hex: "333333"), lineWidth: 1)
                        .padding(3) // inside the dark ring
                )
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func trendIcon(warming: Bool, cooling: Bool) -> String {
        if warming { return "arrow.upper.right" }
        if cooling { return "arrow.lower.right" }
        return "equal"
    }
}

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: Theme.healthy.opacity(isPulsing ? 0.6 : 0), radius: isPulsing ? 4 : 0)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
