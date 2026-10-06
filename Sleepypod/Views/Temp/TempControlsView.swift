import SwiftUI

struct TempControlsView: View {
    @Environment(DeviceManager.self) private var device
    private var target: Int { device.currentSideStatus?.targetTemperatureF ?? 80 }

    var body: some View {
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 28) {
                step("minus", delta: -1)
                Button {
                    Haptics.medium()
                    device.togglePower()
                } label: {
                    if device.isOn {
                        Image(systemName: "power").font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.background)
                            .frame(width: 64, height: 64)
                            .background(Theme.text1, in: Circle())
                    } else {
                        Image(systemName: "power").font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.text1)
                            .frame(width: 64, height: 64)
                            .chromeSurface(Circle())
                    }
                }
                .accessibilityLabel(device.isOn ? "Turn off" : "Turn on")
                step("plus", delta: 1)
            }.buttonStyle(.plain)
        }
    }

    private func step(_ symbol: String, delta: Int) -> some View {
        Button {
            Haptics.light()
            device.setTemperature(target + delta)
        } label: {
            Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(Theme.text1)
                .frame(width: 64, height: 64).chromeSurface(Circle())
        }
        .accessibilityLabel(delta < 0 ? "Decrease temperature" : "Increase temperature")
        .disabled(!device.isOn || (delta < 0 ? target <= 55 : target >= 110))
        .opacity(device.isOn ? 1 : 0.45)
    }
}
