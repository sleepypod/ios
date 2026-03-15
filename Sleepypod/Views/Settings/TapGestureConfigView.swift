import SwiftUI

struct TapGestureConfigView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var leftTaps: TapSettings? { settingsManager.settings?.left.taps }
    private var rightTaps: TapSettings? { settingsManager.settings?.right.taps }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tap Gestures")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)

            Text("Tap on the pod cover to control temperature or alarm")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)

            if let taps = leftTaps {
                sideSection("Left Side", taps: taps, side: .left)
            }

            if let taps = rightTaps {
                Divider().background(Theme.cardBorder)
                sideSection("Right Side", taps: taps, side: .right)
            }
        }
        .cardStyle()
    }

    private func sideSection(_ title: String, taps: TapSettings, side: Side) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.accent)

            tapRow("Double Tap", config: taps.doubleTap, icon: "hand.tap")
            tapRow("Triple Tap", config: taps.tripleTap, icon: "hand.tap")
            tapRow("Quad Tap", config: taps.quadTap, icon: "hand.tap")
        }
    }

    private func tapRow(_ label: String, config: TapConfig, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
                .frame(width: 20)

            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)

            Spacer()

            Text(configDescription(config))
                .font(.caption)
                .foregroundColor(.white)
        }
    }

    private func configDescription(_ config: TapConfig) -> String {
        switch config {
        case .temperature(let change, let amount):
            let dir = change == .increment ? "+" : "-"
            return "\(dir)\(amount)° temp"
        case .alarm(let behavior, _, _):
            return behavior == .snooze ? "Snooze alarm" : "Dismiss alarm"
        }
    }
}
