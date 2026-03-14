import SwiftUI

struct TempControlsView: View {
    @Environment(DeviceManager.self) private var deviceManager

    private var isOn: Bool {
        deviceManager.isOn
    }

    private var offset: Int {
        deviceManager.currentOffset
    }

    var body: some View {
        HStack(spacing: 24) {
            // Minus button
            Button {
                Haptics.light()
                deviceManager.adjustOffset(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 56, height: 56)
                    .background(Theme.cardElevated)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isOn || offset <= TemperatureConversion.minOffset)
            .opacity(!isOn || offset <= TemperatureConversion.minOffset ? 0.4 : 1)

            // Power / OFF button
            Button {
                Haptics.medium()
                deviceManager.togglePower()
            } label: {
                Text(isOn ? "ON" : "OFF")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isOn ? Theme.healthy : Theme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        isOn ? Theme.healthy.opacity(0.15) : Theme.cardElevated
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(isOn ? Theme.healthy : Theme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Plus button
            Button {
                Haptics.light()
                deviceManager.adjustOffset(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 56, height: 56)
                    .background(Theme.cardElevated)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isOn || offset >= TemperatureConversion.maxOffset)
            .opacity(!isOn || offset >= TemperatureConversion.maxOffset ? 0.4 : 1)
        }
    }
}
