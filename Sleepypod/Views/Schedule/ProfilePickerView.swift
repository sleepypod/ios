import SwiftUI

struct ProfilePickerView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @State private var selectedProfile: SleepProfile?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SleepProfile.allCases) { profile in
                let isSelected = selectedProfile == profile
                Button {
                    Haptics.medium()
                    selectedProfile = profile
                    Task {
                        await scheduleManager.applyProfile(profile)
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(profile.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(isSelected ? .white : Theme.textSecondary)
                        Text(profile.subtitle)
                            .font(.caption2)
                            .foregroundColor(isSelected ? .white.opacity(0.7) : Theme.textMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? Theme.accent : Color(hex: "2a2a3a"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
