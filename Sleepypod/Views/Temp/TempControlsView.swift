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
            // Minus button — glass
            Button {
                Haptics.light()
                deviceManager.adjustOffset(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isOn || offset <= TemperatureConversion.minOffset)
            .opacity(!isOn || offset <= TemperatureConversion.minOffset ? 0.4 : 1)

            // Center OFF/power toggle — glass
            Button {
                Haptics.medium()
                deviceManager.togglePower()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isOn ? Theme.healthy : .white.opacity(0.7))
                    .frame(width: 56, height: 56)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isOn ? Theme.healthy.opacity(0.4) : .white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Plus button — glass
            Button {
                Haptics.light()
                deviceManager.adjustOffset(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isOn || offset >= TemperatureConversion.maxOffset)
            .opacity(!isOn || offset >= TemperatureConversion.maxOffset ? 0.4 : 1)
        }
    }
}
