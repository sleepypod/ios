import SwiftUI

struct TempScreen: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        GeometryReader { geo in
            if deviceManager.isConnected {
                ScrollView {
                    VStack(spacing: 0) {
                        // Alerts at top (only when needed)
                        VStack(spacing: 8) {
                            if deviceManager.deviceStatus?.isPriming == true {
                                AlertBanner(
                                    icon: "drop.fill",
                                    title: "Sleepypod is Priming",
                                    message: "Water is being circulated through the system",
                                    style: .info
                                )
                            }
                            if deviceManager.isAlarmActive, let side = deviceManager.alarmSide {
                                AlarmBanner(side: side) {
                                    deviceManager.stopAlarm()
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        VStack(spacing: 24) {
                            TemperatureDialView()
                                .onTapGesture {
                                    Haptics.medium()
                                    deviceManager.togglePower()
                                }

                            TempControlsView()

                            EnvironmentInfoView()
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .refreshable {
                    await deviceManager.fetchStatus()
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                DisconnectedTabView(tab: "Temp")
            }
        }
        .background(Theme.background)
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
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundColor(waterLevelColor)
                Text(waterLevelLabel)
                    .font(.caption)
                    .foregroundColor(waterLevelColor)
            }

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
