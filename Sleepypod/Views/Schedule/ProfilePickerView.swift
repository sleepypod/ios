import SwiftUI

struct ProfilePickerView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @State private var selectedProfile: SleepProfile = .balanced

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Profile", selection: $selectedProfile) {
                ForEach(SleepProfile.allCases) { profile in
                    Text(profile.rawValue).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedProfile) {
                Haptics.medium()
                Task {
                    await scheduleManager.applyProfile(selectedProfile)
                }
            }

            Text(selectedProfile.subtitle)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
    }
}
