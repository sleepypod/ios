import SwiftUI

struct DeviceSettingsCardView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Device Settings")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)

            // Timezone
            VStack(alignment: .leading, spacing: 6) {
                Text("Timezone")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)

                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(Theme.textTertiary)
                    Text(settingsManager.timeZone)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(12)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Temperature format
            VStack(alignment: .leading, spacing: 6) {
                Text("Temperature Unit")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)

                HStack(spacing: 0) {
                    formatButton(title: "CELSIUS", format: .celsius)
                    formatButton(title: "FAHRENHEIT", format: .fahrenheit)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Auto reboot
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Reboot Daily")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("Automatically reboot pod each day")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settingsManager.settings?.rebootDaily ?? false },
                    set: { _ in Task { await settingsManager.toggleRebootDaily() } }
                ))
                .tint(Theme.cooling)
                .labelsHidden()
            }

            // LED Brightness
            VStack(alignment: .leading, spacing: 6) {
                Text("LED Brightness")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)

                HStack(spacing: 8) {
                    Text("Off")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                    // LED brightness is read from DeviceStatus, not PodSettings
                    Slider(value: .constant(50), in: 0...100, step: 1)
                        .tint(Theme.cooling)
                    Text("100%")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
        .cardStyle()
    }

    private func formatButton(title: String, format: TemperatureFormat) -> some View {
        let isSelected = settingsManager.temperatureFormat == format
        return Button {
            Task { await settingsManager.updateTemperatureFormat(format) }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Theme.cooling : Color(hex: "2a2a3a"))
        }
        .buttonStyle(.plain)
    }
}
