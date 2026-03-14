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

    private var targetOffset: Int {
        TemperatureConversion.tempFToOffset(targetTempF)
    }

    private var currentOffset: Int {
        TemperatureConversion.tempFToOffset(currentTempF)
    }

    private var ringColor: Color {
        guard isOn else { return Color(hex: "333333") }
        return TempColor.forOffset(targetOffset)
    }

    private var tempColor: Color {
        guard isOn else { return Theme.textMuted }
        return TempColor.forOffset(targetOffset)
    }

    private var glowColor: Color {
        guard isOn else { return Color.gray.opacity(0.2) }
        return TempColor.glowForOffset(targetOffset)
    }

    /// "WARMING TO" or "COOLING TO" based on offset direction
    private var directionLabel: String? {
        guard isOn else { return nil }
        if targetOffset > 0 { return "WARMING TO" }
        if targetOffset < 0 { return "COOLING TO" }
        return nil
    }

    var body: some View {
        ZStack {
            // Outer glow layer (blurred for soft glow)
            Circle()
                .stroke(ringColor.opacity(0.3), lineWidth: 8)
                .frame(width: dialSize, height: dialSize)
                .blur(radius: 6)

            // Main thick ring
            Circle()
                .stroke(ringColor, lineWidth: 6)
                .frame(width: dialSize, height: dialSize)
                .shadow(color: glowColor, radius: 40)
                .shadow(color: glowColor, radius: 20)
                .shadow(color: glowColor, radius: 10)

            // Center content
            VStack(spacing: 4) {
                if isOn {
                    // Direction label: "WARMING TO" / "COOLING TO"
                    if let label = directionLabel {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(tempColor.opacity(0.8))
                            .padding(.bottom, 2)
                    }

                    // Primary: offset display (+2, -1, 0)
                    Text(TemperatureConversion.offsetDisplay(targetOffset))
                        .font(.system(size: 72, weight: .light, design: .rounded))
                        .foregroundColor(tempColor)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: targetOffset)

                    // Absolute target temp below offset
                    Text(absoluteTempDisplay)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 2)

                    // "NOW" row: current offset + current temp
                    HStack(spacing: 6) {
                        Text("NOW")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(Theme.textMuted)

                        Text("\(TemperatureConversion.offsetDisplay(currentOffset)) \u{00B7} \(currentTempDisplay)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.top, 6)

                    // Time remaining
                    if let remaining = sideStatus?.secondsRemaining, remaining > 0 {
                        Text(formatRemaining(remaining))
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                            .padding(.top, 2)
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

    /// Absolute target temp: "84° F" or "29° C"
    private var absoluteTempDisplay: String {
        TemperatureConversion.displayTemp(targetTempF, format: settingsManager.temperatureFormat)
    }

    /// Current temp display for the NOW row
    private var currentTempDisplay: String {
        TemperatureConversion.displayTemp(currentTempF, format: settingsManager.temperatureFormat)
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
