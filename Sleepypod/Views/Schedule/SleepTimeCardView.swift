import SwiftUI

struct SleepTimeCardView: View {
    @Environment(ScheduleManager.self) private var scheduleManager

    private var daily: DailySchedule? {
        scheduleManager.currentDailySchedule
    }

    private var bedtime: String {
        guard let daily else { return "—" }
        return formatTime(daily.power.on)
    }

    private var wakeTime: String {
        guard let daily else { return "—" }
        return formatTime(daily.alarm.time)
    }

    private var duration: String {
        guard let daily else { return "—" }
        let onParts = daily.power.on.split(separator: ":")
        let offParts = daily.alarm.time.split(separator: ":")
        guard onParts.count == 2, offParts.count == 2,
              let onH = Int(onParts[0]), let onM = Int(onParts[1]),
              let offH = Int(offParts[0]), let offM = Int(offParts[1]) else { return "—" }

        var totalMinutes = (offH * 60 + offM) - (onH * 60 + onM)
        if totalMinutes < 0 { totalMinutes += 24 * 60 }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    var body: some View {
        HStack(spacing: 0) {
            timeItem(icon: "moon.fill", value: bedtime, label: "Bedtime", color: Theme.purple)
            Divider()
                .frame(height: 40)
                .background(Theme.cardBorder)
            timeItem(icon: "sun.max.fill", value: wakeTime, label: "Wake", color: Theme.amber)
            Divider()
                .frame(height: 40)
                .background(Theme.cardBorder)
            timeItem(icon: "clock.fill", value: duration, label: "Duration", color: Theme.textSecondary)
        }
        .cardStyle()
    }

    private func timeItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
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
