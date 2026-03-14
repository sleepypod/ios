import SwiftUI

struct PhaseBlockView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager
    let phase: SchedulePhase

    private var tempColor: Color {
        TempColor.forOffset(phase.offset)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Phase indicator dot
            Circle()
                .fill(tempColor)
                .frame(width: 10, height: 10)

            // Phase icon
            Image(systemName: phase.icon)
                .font(.system(size: 16))
                .foregroundColor(tempColor)
                .frame(width: 24)

            // Phase info
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Text(formatTime(phase.time))
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            // Temperature controls
            HStack(spacing: 12) {
                Button {
                    Task {
                        await scheduleManager.updatePhaseTemperature(time: phase.time, delta: -1)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.cardElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(tempDisplay)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(tempColor)
                    .frame(minWidth: 50)
                    .contentTransition(.numericText())

                Button {
                    Task {
                        await scheduleManager.updatePhaseTemperature(time: phase.time, delta: 1)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.cardElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var tempDisplay: String {
        TemperatureConversion.displayTemp(phase.temperatureF, format: settingsManager.temperatureFormat)
    }

    private func formatTime(_ time: String) -> String {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return time }

        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):\(String(format: "%02d", minute)) \(period)"
    }
}
