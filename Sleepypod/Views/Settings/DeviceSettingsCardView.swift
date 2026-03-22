import SwiftUI

struct DeviceSettingsCardView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(StatusManager.self) private var statusManager
    @Environment(DeviceManager.self) private var deviceManager
    @State private var ledValue: Double = 50
    @State private var rebootTime: Date = {
        // Default 3:00 AM
        var comps = DateComponents()
        comps.hour = 3
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()

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
                    formatButton(title: "\u{00B0}F", format: .fahrenheit)
                    formatButton(title: "\u{00B0}C", format: .celsius)
                    formatButton(title: "+/-", format: .relative)
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

            // Reboot time picker (visible when reboot is enabled)
            if settingsManager.settings?.rebootDaily == true {
                DatePicker("Reboot Time", selection: $rebootTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .tint(Theme.accent)
                    .onChange(of: rebootTime) { _, newValue in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        let timeString = formatter.string(from: newValue)
                        Task { await settingsManager.updateRebootTime(timeString) }
                    }
            }

            // Auto Prime Daily
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Prime Daily")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("Runs 1 hour after daily reboot")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settingsManager.settings?.primePodDaily.enabled ?? false },
                    set: { _ in Haptics.medium(); Task { await settingsManager.togglePrimePodDaily() } }
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
        }
        .cardStyle()
        .onAppear {
            syncRebootTime()
        }
        .onChange(of: settingsManager.settings?.rebootTime) { _, _ in
            syncRebootTime()
        }
    }

    private func syncRebootTime() {
        let timeStr = settingsManager.settings?.rebootTime ?? "03:00"
        let parts = timeStr.split(separator: ":")
        if parts.count == 2,
           let hour = Int(parts[0]),
           let minute = Int(parts[1]) {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            if let date = Calendar.current.date(from: comps) {
                rebootTime = date
            }
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

// MARK: - Sides Card

struct SidesCardView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sides")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)

            if let settings = settingsManager.settings {
                // Left side
                sideRow(
                    badge: "L",
                    label: "Left Side",
                    name: settings.left.name,
                    placeholder: "Left",
                    awayMode: settings.left.awayMode,
                    side: .left
                )

                Divider().background(Theme.cardBorder)

                // Right side
                sideRow(
                    badge: "R",
                    label: "Right Side",
                    name: settings.right.name,
                    placeholder: "Right",
                    awayMode: settings.right.awayMode,
                    side: .right
                )
            }
        }
        .cardStyle()
    }

    private func sideRow(badge: String, label: String, name: String, placeholder: String, awayMode: Bool, side: Side) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accent.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)

                    SideNameTextField(
                        placeholder: placeholder,
                        initialValue: name
                    ) { newName in
                        Task { await settingsManager.updateSideName(side, name: newName) }
                    }
                }
                Spacer()
            }

            HStack {
                Text("Away Mode")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { awayMode },
                    set: { _ in
                        Haptics.medium()
                        Task { await settingsManager.toggleAwayMode(side) }
                    }
                ))
                .tint(Theme.cooling)
                .labelsHidden()
            }
        }
    }
}
