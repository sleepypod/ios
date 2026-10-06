import SwiftUI

struct HealthAccessView: View {
    @Environment(HealthSyncService.self) private var health
    @Environment(UserProfile.self) private var profile
    @Environment(ScheduleManager.self) private var schedule
    var onComplete: (() -> Void)?
    @State private var requesting = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 30

    var body: some View {
        @Bindable var health = health
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "heart").font(.system(size: 24)).foregroundStyle(Theme.red)
                        .frame(width: 56, height: 56)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.border2, lineWidth: 1))
                        .accessibilityHidden(true)
                    Text("Sync with Apple Health").font(.system(size: titleSize, weight: .bold)).tracking(-0.5)
                    Text("Each morning, last night's sleep and vitals are written to Health. Stage analysis runs on this iPhone.")
                        .font(.subheadline).foregroundStyle(Theme.text2).lineSpacing(3)
                }
                .padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 16) {
                    GroupedSection("WRITE") {
                        GroupedCard {
                            SettingsRow("Sleep stages") { Toggle("Sleep stages", isOn: $health.preferences.sleep).labelsHidden() }
                            SettingsRow("Heart rate") { Toggle("Heart rate", isOn: $health.preferences.heartRate).labelsHidden() }
                            SettingsRow("Heart rate variability") { Toggle("Heart rate variability", isOn: $health.preferences.hrv).labelsHidden() }
                            SettingsRow("Respiratory rate") { Toggle("Respiratory rate", isOn: $health.preferences.respiration).labelsHidden() }
                        }
                    }
                    GroupedSection("READ") {
                        GroupedCard {
                            SettingsRow("Sleep schedule", subtitle: "Sets bedtime and wake in Schedule", height: 56) {
                                Toggle("Sleep schedule", isOn: $health.preferences.readSleep).labelsHidden()
                            }
                        }
                    }
                    if onComplete == nil {
                        GroupedSection("THIS iPHONE") {
                            GroupedCard {
                                SettingsRow("Sync this iPhone's side") {
                                    Toggle("Sync this iPhone's side", isOn: $health.enabled).labelsHidden()
                                }
                            }
                        }
                        allowButton.padding(.top, 8)
                    }
                    if let error = health.authorizationError {
                        Text(error).font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 16)
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 16)
            .padding(.top, onComplete == nil ? 8 : 30)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if let onComplete {
                VStack(spacing: 6) {
                    allowButton
                    Button("Not now") { health.enabled = false; onComplete() }
                        .font(.callout.weight(.medium)).foregroundStyle(Theme.text2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, 16).padding(.bottom, 4)
                .background(Theme.background)
            }
        }
        .background(Theme.background).tint(Theme.green)
        .navigationTitle(onComplete == nil ? "Apple Health" : "").navigationBarTitleDisplayMode(.inline)
    }

    private var allowButton: some View {
        Button(requesting ? "Requesting access…" : "Allow Health access") {
            requesting = true
            Task {
                if await health.requestAuthorization() {
                    if health.preferences.readSleep { await importSchedule() }
                    onComplete?()
                }
                requesting = false
            }
        }
        .buttonStyle(PrimaryButtonStyle()).disabled(requesting)
    }

    private func importSchedule() async {
        guard let times = await health.inferredSchedule() else { return }
        schedule.selectedSide = profile.defaultSide == .left ? .left : .right
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        await schedule.fetchSchedules()
        await schedule.updateBedtime(formatter.string(from: times.bed))
        if var power = schedule.currentDailySchedule?.power {
            power.off = formatter.string(from: times.wake)
            await schedule.updatePowerSchedule(power)
        }
    }
}
