import SwiftUI

struct SleepTimeCardView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @State private var showBedtimePicker = false
    @State private var showWakePicker = false

    private var daily: DailySchedule? { scheduleManager.currentDailySchedule }

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
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Bedtime — tappable
            Button { Haptics.light(); showBedtimePicker = true } label: {
                timeItem(icon: "moon.fill", value: bedtime, label: "Bedtime", color: Theme.purple)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 40).background(Theme.cardBorder)

            // Wake — tappable
            Button { Haptics.light(); showWakePicker = true } label: {
                timeItem(icon: "sun.max.fill", value: wakeTime, label: "Wake", color: Theme.amber)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 40).background(Theme.cardBorder)

            timeItem(icon: "clock.fill", value: duration, label: "Duration", color: Theme.textSecondary)
        }
        .cardStyle()
        .sheet(isPresented: $showBedtimePicker) {
            TimePickerSheet(
                title: "Bedtime",
                currentTime: daily?.power.on ?? "22:00"
            ) { newTime in
                Task { await scheduleManager.updateBedtime(newTime) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWakePicker) {
            TimePickerSheet(
                title: "Wake Time",
                currentTime: daily?.alarm.time ?? "07:00"
            ) { newTime in
                Task { await scheduleManager.updateAlarmTime(newTime) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
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
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return time }
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):\(String(format: "%02d", minute)) \(period)"
    }
}

// MARK: - Time Picker Sheet

private struct TimePickerSheet: View {
    let title: String
    let currentTime: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                DatePicker(title, selection: $selectedDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                Button {
                    Haptics.medium()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    onSave(formatter.string(from: selectedDate))
                    dismiss()
                } label: {
                    Text("Set \(title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textMuted)
                }
            }
            .onAppear {
                let parts = currentTime.split(separator: ":")
                if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                    components.hour = h
                    components.minute = m
                    selectedDate = Calendar.current.date(from: components) ?? Date()
                }
            }
        }
    }
}
