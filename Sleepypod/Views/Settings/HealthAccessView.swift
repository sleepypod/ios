import SwiftUI

struct HealthAccessView: View {
    @Environment(HealthSyncService.self) private var health
    @Environment(UserProfile.self) private var profile
    @Environment(ScheduleManager.self) private var schedule
    @Environment(SettingsManager.self) private var settings
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
                            SettingsRow("Heart rate, HRV, breathing", subtitle: "Compares the pod with your Apple Watch", height: 56) {
                                Toggle("Heart rate, HRV, breathing", isOn: $health.preferences.readVitals).labelsHidden()
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
                        syncStatus
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

    /// What actually reached Health, so a sync can be checked on a real device.
    private var syncStatus: some View {
        GroupedSection("SYNC") {
            GroupedCard {
                SettingsRow("Side", icon: "bed.double") { RowValue(settings.sideName(for: profile.defaultSide)) }
                SettingsRow("Nights saved", icon: "heart", iconColor: Theme.red) { RowValue("\(health.receipts.count)", mono: true) }
                SettingsRow("Last saved", icon: "clock") {
                    RowValue(health.receipts.values.map(\.date).max()?.formatted(date: .abbreviated, time: .shortened) ?? "Never", mono: true)
                }
                ForEach(Array(Set(health.failures.values)).sorted(), id: \.self) { message in
                    let count = health.failures.values.filter { $0 == message }.count
                    SettingsRow(message, icon: "exclamationmark.triangle", iconColor: Theme.amber, titleFont: .footnote) {
                        RowValue(count == 1 ? "1 night" : "\(count) nights", mono: true)
                    }
                }
                Button {
                    Task {
                        await health.syncRecent(api: APIBackend.current.createClient(), podID: settings.podID,
                                                side: profile.defaultSide, demo: APIBackend.current.isDemo)
                    }
                } label: {
                    SettingsRow(health.isSyncing ? "Syncing…" : "Sync last 7 nights now", icon: "arrow.triangle.2.circlepath") {
                        if health.isSyncing { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(health.isSyncing || !health.enabled || APIBackend.current.isDemo)
            }
            if APIBackend.current.isDemo {
                Text("Demo mode never writes to Apple Health. Connect a pod to sync.")
                    .font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 16)
            }
        }
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
