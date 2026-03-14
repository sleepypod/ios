import SwiftUI

struct ScheduleScreen: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Side selector
                ScheduleSideSelectorView()

                // Day selector
                DaySelectorView()

                // Profile picker
                ProfilePickerView()

                // Sleep time card
                SleepTimeCardView()

                // Schedule active toggle
                scheduleToggle

                // Phase blocks
                if scheduleManager.schedules != nil {
                    VStack(spacing: 12) {
                        ForEach(scheduleManager.phases) { phase in
                            PhaseBlockView(phase: phase)
                        }
                    }
                } else if scheduleManager.isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(40)
                } else {
                    Text("No schedule data")
                        .foregroundColor(Theme.textSecondary)
                        .padding(40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .task {
            await scheduleManager.fetchSchedules()
        }
    }

    private var scheduleToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule Active")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Text("Automatically adjust temperature")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: .constant(scheduleManager.currentDailySchedule?.power.enabled ?? false))
                .tint(Theme.cooling)
                .labelsHidden()
        }
        .cardStyle()
    }
}

// MARK: - Schedule Side Selector

private struct ScheduleSideSelectorView: View {
    @Environment(ScheduleManager.self) private var scheduleManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach([SideSelection.left, .right, .both], id: \.self) { selection in
                let isSelected = scheduleManager.selectedSide == selection
                Button {
                    scheduleManager.selectedSide = selection
                } label: {
                    Text(label(for: selection))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color(hex: "1e2a3a") : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func label(for selection: SideSelection) -> String {
        switch selection {
        case .left: "Left"
        case .right: "Right"
        case .both: "Both"
        }
    }
}

extension SideSelection: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .left: hasher.combine("left")
        case .right: hasher.combine("right")
        case .both: hasher.combine("both")
        }
    }
}
