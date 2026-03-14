import SwiftUI

struct TemperatureDialView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    private let dialSize: CGFloat = 280

    private var sideStatus: SideStatus? {
        deviceManager.currentSideStatus
    }

    private var isOn: Bool {
        sideStatus?.isOn ?? false
    }

    private var targetTempF: Int {
        sideStatus?.targetTemperatureF ?? 80
    }

    private var currentTempF: Int {
        sideStatus?.currentTemperatureF ?? 80
    }

    private var offset: Int {
        TemperatureConversion.tempFToOffset(targetTempF)
    }

    private var ringColor: Color {
        guard isOn else { return Color(hex: "333333") }
        return TempColor.forOffset(offset)
    }

    private var tempColor: Color {
        guard isOn else { return Theme.textMuted }
        return TempColor.forOffset(offset)
    }

    private var glowColor: Color {
        guard isOn else { return Color.gray.opacity(0.2) }
        return TempColor.glowForOffset(offset)
    }

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(ringColor, lineWidth: 4)
                .frame(width: dialSize, height: dialSize)
                .shadow(color: glowColor, radius: 30)
                .shadow(color: glowColor, radius: 15)

            // Center content
            VStack(spacing: 4) {
                if isOn {
                    // Target temperature
                    Text(tempDisplay)
                        .font(.system(size: 72, weight: .light, design: .rounded))
                        .foregroundColor(tempColor)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: targetTempF)

                    // Unit label
                    Text(unitLabel)
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)

                    // Current temp
                    if currentTempF != targetTempF {
                        Text("Currently \(currentTempDisplay)")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                            .padding(.top, 4)
                    }

                    // Status
                    if let remaining = sideStatus?.secondsRemaining, remaining > 0 {
                        Text(formatRemaining(remaining))
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                    }
                } else {
                    Text("OFF")
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private var tempDisplay: String {
        let format = settingsManager.temperatureFormat
        switch format {
        case .fahrenheit:
            return "\(targetTempF)"
        case .celsius:
            let c = TemperatureConversion.tempFToC(targetTempF)
            return "\(Int(round(c)))"
        }
    }

    private var currentTempDisplay: String {
        TemperatureConversion.displayTemp(currentTempF, format: settingsManager.temperatureFormat)
    }

    private var unitLabel: String {
        switch settingsManager.temperatureFormat {
        case .fahrenheit: "°F"
        case .celsius: "°C"
        }
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        }
        return "\(minutes)m remaining"
    }
}
