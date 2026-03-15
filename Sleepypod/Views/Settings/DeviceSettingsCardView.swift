import SwiftUI

struct DeviceSettingsCardView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(StatusManager.self) private var statusManager
    @Environment(DeviceManager.self) private var deviceManager
    @State private var ledValue: Double = 50

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
                    set: { _ in Haptics.medium(); Task { await settingsManager.toggleRebootDaily() } }
                ))
                .tint(Theme.cooling)
                .labelsHidden()
            }

            // LED Brightness
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LED Brightness")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(ledValue))%")
                        .font(.caption.monospaced())
                        .foregroundColor(Theme.textSecondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "light.min")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                    Slider(value: $ledValue, in: 0...100, step: 1)
                        .tint(Theme.cooling)
                    Image(systemName: "light.max")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
            }
            .onAppear {
                ledValue = Double(deviceManager.deviceStatus?.settings.ledBrightness ?? 50)
            }

            // Services
            if let services = statusManager.services {
                Divider().background(Theme.cardBorder)

                serviceToggle(
                    title: "Biometrics",
                    description: "Sleep tracking and analysis",
                    isOn: services.biometrics.enabled
                ) {
                    Task { await statusManager.toggleBiometrics() }
                }

                serviceToggle(
                    title: "Sentry Logging",
                    description: "Error reporting service",
                    isOn: services.sentryLogging.enabled
                ) {
                    Task { await statusManager.toggleSentryLogging() }
                }
            }
        }
        .cardStyle()
    }

    private func serviceToggle(title: String, description: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in Haptics.medium(); action() }))
                .tint(Theme.cooling)
                .labelsHidden()
        }
    }

    private func formatButton(title: String, format: TemperatureFormat) -> some View {
        let isSelected = settingsManager.temperatureFormat == format
        return Button {
            Haptics.tap()
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
