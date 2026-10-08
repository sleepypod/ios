import SwiftUI

struct DaySelectorView: View {
    @Environment(ScheduleManager.self) private var scheduleManager

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DayOfWeek.weekdays) { day in
                let isSelected = scheduleManager.selectedDays.contains(day)
                Button {
                    Haptics.tap()
                    if isSelected && scheduleManager.selectedDays.count > 1 {
                        scheduleManager.selectedDays.remove(day)
                    } else if !isSelected {
                        scheduleManager.selectedDays.insert(day)
                    }
                    scheduleManager.selectedDay = scheduleManager.selectedDays.contains(day) ? day : (DayOfWeek.weekdays.first { scheduleManager.selectedDays.contains($0) } ?? day)
                } label: {
                    Text(day.shortLabel)
                        .font(.mono(13, relativeTo: .footnote))
                        .foregroundStyle(isSelected ? Theme.background : Theme.text2)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(isSelected ? Theme.text1 : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.border2, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
