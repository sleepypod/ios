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
            // Minus button — filled gray circle
            Button {
                Haptics.light()
                deviceManager.adjustOffset(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color(hex: "2a2a2a"))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isOn || offset <= TemperatureConversion.minOffset)
            .opacity(!isOn || offset <= TemperatureConversion.minOffset ? 0.4 : 1)

            // Center OFF/power toggle
            Button {
                Haptics.medium()
                deviceManager.togglePower()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                    Text("OFF")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(isOn ? Theme.healthy : Theme.textSecondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    isOn ? Theme.healthy.opacity(0.15) : Theme.cardElevated
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isOn ? Theme.healthy.opacity(0.4) : Theme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Plus button — white outline circle
            Button {
                Haptics.light()
                deviceManager.adjustOffset(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.clear)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "444444"), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isOn || offset >= TemperatureConversion.maxOffset)
            .opacity(!isOn || offset >= TemperatureConversion.maxOffset ? 0.4 : 1)
        }
    }
}
