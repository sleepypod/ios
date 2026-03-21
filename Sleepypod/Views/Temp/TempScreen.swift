import SwiftUI

struct TempScreen: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var bgPulse = false

    private var ambientColor: Color {
        guard deviceManager.isConnected, deviceManager.isOn else { return .clear }
        let status = deviceManager.currentSideStatus
        let target = status?.targetTemperatureF ?? 80
        let current = status?.currentTemperatureF ?? 80
        return TempColor.forDelta(target: target, current: current)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full-screen ambient glow
                if deviceManager.isConnected && deviceManager.isOn {
                    RadialGradient(
                        colors: [
                            ambientColor.opacity(bgPulse ? 0.3 : 0.18),
                            ambientColor.opacity(bgPulse ? 0.12 : 0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: geo.size.height * (bgPulse ? 0.75 : 0.65)
                    )
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: bgPulse)
                    .animation(.easeInOut(duration: 1.0), value: ambientColor)
                    .onAppear { bgPulse = true }
                }

                if deviceManager.isConnected {
                    VStack(spacing: 0) {
                        // Top bar — priming indicator + profile
                        HStack {
                            if deviceManager.deviceStatus?.isPriming == true {
                                PrimingIndicator()
                            }
                            Spacer()
                            UserSelectorView()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 4)

                    ScrollView {
                        VStack(spacing: 0) {
                            // Side selector
                            SideSelectorView()
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 12)

                            // Alerts
                            VStack(spacing: 8) {
                                if deviceManager.isAlarmActive, let side = deviceManager.alarmSide {
                                    AlarmBanner(side: side) {
                                        deviceManager.stopAlarm()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)

                            // Dial + controls
                            VStack(spacing: 32) {
                                TemperatureDialView()
                                    .onTapGesture {
                                        Haptics.medium()
                                        deviceManager.togglePower()
                                    }

                                TempControlsView()

                                EnvironmentInfoView()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    }
                    .refreshable {
                        await deviceManager.fetchStatus()
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    } // VStack
                } else {
                    DisconnectedTabView(tab: "Temp")
                }
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
            Button {
                Haptics.medium()
                Task {
                    _ = try? await APIBackend.current.createClient().snoozeAlarm(side: side, duration: 300)
                }
            } label: {
                Text("Snooze")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(hex: "e0c080"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "e0c080").opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
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
    @State private var ambientLight: AmbientLightReading?

    private var ambientTempF: Int {
        deviceManager.currentSideStatus?.currentTemperatureF ?? 0
    }

    private var autoOffText: String? {
        guard let remaining = deviceManager.currentSideStatus?.secondsRemaining, remaining > 0 else { return nil }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 20) {
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

            if let autoOff = autoOffText {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    Text(autoOff)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }

            if let light = ambientLight {
                HStack(spacing: 6) {
                    Image(systemName: light.lux < 10 ? "moon.fill" : "sun.max.fill")
                        .font(.caption)
                        .foregroundColor(light.lux < 10 ? Theme.purple : Theme.amber)
                    Text("\(Int(light.lux)) lux")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .task {
            ambientLight = try? await APIBackend.current.createClient().getAmbientLightLatest()
        }
    }
}
