import SwiftUI

struct TempScreen: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header bar: WiFi + power
                headerBar

                // Connection banner
                if !deviceManager.isConnected {
                    ConnectionBanner()
                }

                // Priming alert
                if deviceManager.deviceStatus?.isPriming == true {
                    AlertBanner(
                        icon: "drop.fill",
                        title: "Pod is Priming",
                        message: "Water is being circulated through the system",
                        style: .info
                    )
                }

                // Alarm banner
                if deviceManager.isAlarmActive, let side = deviceManager.alarmSide {
                    AlarmBanner(side: side) {
                        deviceManager.stopAlarm()
                    }
                }

                // Temperature dial (tap to toggle power)
                TemperatureDialView()
                    .onTapGesture {
                        Haptics.medium()
                        deviceManager.togglePower()
                    }

                // Controls (+/- and OFF)
                TempControlsView()

                // Environment info (water + ambient temp)
                EnvironmentInfoView()
                    .padding(.top, 4)

                // Side selector (between env info and bottom)
                SideSelectorView()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .task {
            deviceManager.startPolling()
            await deviceManager.fetchStatus()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: wifiIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(wifiColor)
                Text("\(deviceManager.deviceStatus?.wifiStrength ?? 0)%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(wifiColor)
            }

            Spacer()

            Button {
                Haptics.medium()
                deviceManager.togglePower()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(deviceManager.isOn ? Theme.healthy : .white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(deviceManager.isOn ? Theme.healthy.opacity(0.4) : .white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var wifiIcon: String {
        let strength = deviceManager.deviceStatus?.wifiStrength ?? 0
        if strength > 0 { return "wifi" }
        return "wifi.slash"
    }

    private var wifiColor: Color {
        let strength = deviceManager.deviceStatus?.wifiStrength ?? 0
        if strength >= 50 { return Theme.healthy }
        if strength >= 25 { return Theme.amber }
        return Theme.error
    }
}

// MARK: - Connection Banner

private struct ConnectionBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundColor(Theme.error)
            Text("Not connected to pod")
                .font(.subheadline)
                .foregroundColor(Theme.error)
            Spacer()
        }
        .padding(12)
        .background(Theme.error.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.error.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Alert Banner

enum AlertBannerStyle {
    case info, warning

    var bgGradient: LinearGradient {
        switch self {
        case .info:
            LinearGradient(colors: [Color(hex: "1e3c50").opacity(0.8), Color(hex: "143246").opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warning:
            LinearGradient(colors: [Color(hex: "503c1e").opacity(0.8), Color(hex: "3c2d14").opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var borderColor: Color {
        switch self {
        case .info: Color(hex: "468ca0").opacity(0.4)
        case .warning: Color(hex: "b48c3c").opacity(0.4)
        }
    }

    var textColor: Color {
        switch self {
        case .info: Color(hex: "8ecfcf")
        case .warning: Color(hex: "e0c080")
        }
    }
}

private struct AlertBanner: View {
    let icon: String
    let title: String
    let message: String
    let style: AlertBannerStyle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(style.textColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(style.textColor)
                Text(message)
                    .font(.caption)
                    .foregroundColor(style.textColor.opacity(0.7))
            }
            Spacer()
        }
        .padding(12)
        .background(style.bgGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Alarm Banner

private struct AlarmBanner: View {
    let side: Side
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .foregroundColor(Color(hex: "e0c080"))
            VStack(alignment: .leading, spacing: 2) {
                Text("Alarm Active")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color(hex: "e0c080"))
                Text("\(side.displayName) side alarm is vibrating")
                    .font(.caption)
                    .foregroundColor(Color(hex: "e0c080").opacity(0.7))
            }
            Spacer()
            Button("Stop") {
                Haptics.heavy()
                onStop()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.error)
            .clipShape(Capsule())
        }
        .padding(12)
        .background(
            LinearGradient(colors: [Color(hex: "503c1e").opacity(0.8), Color(hex: "3c2d14").opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "b48c3c").opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Environment Info

private struct EnvironmentInfoView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    private var waterLevelLabel: String {
        guard let level = deviceManager.deviceStatus?.waterLevel else { return "---" }
        switch level.lowercased() {
        case "true", "ok", "full", "good": return "Water OK"
        case "false", "low", "empty": return "Water Low"
        default: return "Water: \(level)"
        }
    }

    private var waterLevelColor: Color {
        guard let level = deviceManager.deviceStatus?.waterLevel else { return Theme.textMuted }
        switch level.lowercased() {
        case "true", "ok", "full", "good": return Theme.healthy
        case "false", "low", "empty": return Theme.amber
        default: return Theme.textSecondary
        }
    }

    private var ambientTempF: Int {
        deviceManager.currentSideStatus?.currentTemperatureF ?? 0
    }

    var body: some View {
        HStack(spacing: 28) {
            // Water level
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundColor(waterLevelColor)
                Text(waterLevelLabel)
                    .font(.caption)
                    .foregroundColor(waterLevelColor)
            }

            // Ambient / current temp (inside)
            if ambientTempF > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    Text("\(TemperatureConversion.displayTemp(ambientTempF, format: settingsManager.temperatureFormat))  Inside")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}
