import SwiftUI

struct DaySelectorView: View {
    @Environment(ScheduleManager.self) private var scheduleManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DayOfWeek.weekdays) { day in
                let isSelected = scheduleManager.selectedDays.contains(day)
                Button {
                    Haptics.tap()
                    if isSelected && scheduleManager.selectedDays.count > 1 {
                        scheduleManager.selectedDays.remove(day)
                    } else if !isSelected {
                        scheduleManager.selectedDays.insert(day)
                    }
                    scheduleManager.selectedDay = day
                } label: {
                    Text(day.shortLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : Theme.textMuted)
                        .frame(width: 38, height: 38)
                        .background(isSelected ? Theme.cooling : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
