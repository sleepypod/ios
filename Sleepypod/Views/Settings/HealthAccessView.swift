import SwiftUI

struct HealthAccessView: View {
    @Environment(HealthSyncService.self) private var health
    @Environment(UserProfile.self) private var profile
    @Environment(ScheduleManager.self) private var schedule
    @Environment(SettingsManager.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var requesting = false
    @State private var confirmRebuild = false
    @State private var rebuildFailed = false
    @State private var rebuildStart = Calendar.current.date(byAdding: .day, value: -HealthSyncService.rebuildDays, to: .now) ?? .now
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
                    Text("Your Health data stays on this iPhone unless you send your Apple Watch readings to your own pod below, over your home network. sleepypod has no server: nothing goes to iCloud or anyone else.")
                        .font(.footnote).foregroundStyle(Theme.text2).lineSpacing(3)
                }
                .padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 16) {
                    GroupedSection("WRITE") {
                        GroupedCard {
                            SettingsRow("Sleep stages") { Toggle("Sleep stages", isOn: $health.preferences.sleep).labelsHidden() }
                            SettingsRow("Heart rate") { Toggle("Heart rate", isOn: $health.preferences.heartRate).labelsHidden() }
                            SettingsRow("Resting heart rate") { Toggle("Resting heart rate", isOn: $health.preferences.restingHeartRate).labelsHidden() }
                            SettingsRow("Heart rate variability") { Toggle("Heart rate variability", isOn: $health.preferences.hrv).labelsHidden() }
                            if health.preferences.hrv {
                                SettingsRow("HRV readings") {
                                    Picker("HRV readings", selection: $health.preferences.hrvFormat) {
                                        Text("Every 5 minutes").tag(HealthSyncService.Preferences.HRVFormat.windows)
                                        Text("Nightly average").tag(HealthSyncService.Preferences.HRVFormat.nightly)
                                    }
                                    .labelsHidden().pickerStyle(.menu)
                                }
                            }
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
                    GroupedSection("THIS iPHONE") {
                        GroupedCard {
                            SettingsRow("Sync this iPhone's side") {
                                Toggle("Sync this iPhone's side", isOn: $health.enabled).labelsHidden()
                            }
                        }
                    }
                    if health.authorizationDenied { deniedNote } else { allowButton.padding(.top, 8) }
                    syncStatus
                    if APIBackend.current.supportsWatchUpload {
                        podUpload
                    } else if APIBackend.current == .freeSleep {
                        Text("Sending Apple Watch readings to the pod needs the sleepypod server; Free Sleep doesn't store them.")
                            .font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 16)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = health.authorizationError {
                        Text(error).font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 16)
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background).tint(Theme.green)
        .navigationTitle("Apple Health").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Rewrite Apple Health data?", isPresented: $confirmRebuild, titleVisibility: .visible) {
            Button("Rewrite", role: .destructive) { rebuild() }
        } message: {
            Text("Rewrites every night since \(rebuildStart.formatted(date: .abbreviated, time: .omitted)) from the pod with the current analysis, then deletes anything else sleepypod wrote to Health in that period. Earlier nights, Apple Watch and other apps' data aren't touched. Keep the app open until it finishes.")
        }
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
                    Haptics.light()
                    Task {
                        await health.syncRecent(api: APIBackend.current.createClient(), podID: settings.podID,
                                                side: profile.defaultSide, demo: APIBackend.current.isDemo)
                        if health.failures.isEmpty && health.authorizationError == nil { Haptics.success() } else { Haptics.warning() }
                    }
                } label: {
                    SettingsRow(health.isSyncing ? "Syncing…" : "Sync last 7 nights now", icon: "arrow.triangle.2.circlepath") {
                        if health.isSyncing { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(health.isSyncing || !health.enabled || APIBackend.current.isDemo)
                SettingsRow("Rewrite nights since", icon: "calendar") {
                    DatePicker("Rewrite nights since", selection: $rebuildStart,
                               in: ...(Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now), displayedComponents: .date)
                        .labelsHidden()
                }
                .disabled(health.isSyncing)
                Button {
                    Haptics.light()
                    confirmRebuild = true
                } label: {
                    SettingsRow(rebuildTitle, icon: "arrow.counterclockwise", iconColor: Theme.amber) {
                        if health.rebuildProgress != nil { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(health.isSyncing || !health.enabled || APIBackend.current.isDemo)
            }
            if rebuildFailed {
                Text("The rewrite stopped before every night was rewritten, so older Health data was kept. Fix the errors above and try again.")
                    .font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 16)
            }
            if APIBackend.current.isDemo {
                Text("Demo mode never writes to Apple Health. Connect a pod to sync.")
                    .font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 16)
            }
        }
    }

    /// Opt-in: the Watch's own stages and vitals go to the pod, which scores its staging against them.
    private var podUpload: some View {
        @Bindable var health = health
        return GroupedSection("SEND TO POD") {
            GroupedCard {
                SettingsRow("Send Watch data each morning", subtitle: "Sleep stages, heart rate, HRV, breathing", height: 56) {
                    Toggle("Send Watch data each morning", isOn: $health.preferences.sendWatchToPod).labelsHidden()
                }
                Button {
                    Haptics.light()
                    Task {
                        let report = await health.sendWatchData(api: APIBackend.current.createClient(), side: profile.defaultSide,
                                                                days: HealthSyncService.podUploadDays)
                        if report != nil && health.podUploadError == nil { Haptics.success() } else { Haptics.warning() }
                    }
                } label: {
                    SettingsRow(health.isSendingToPod ? "Sending…" : "Send last \(HealthSyncService.podUploadDays) days now",
                                icon: "arrow.up.circle") {
                        if health.isSendingToPod { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(health.isSendingToPod || !health.enabled)
                if let last = health.lastPodUpload {
                    SettingsRow("Last sent", subtitle: Self.podUploadSummary(last.report), icon: "clock", height: 56) {
                        RowValue(last.date.formatted(date: .omitted, time: .shortened), mono: true)
                    }
                }
            }
            if let error = health.podUploadError {
                Text(error).font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 16)
            }
            Text("Your pod compares its sleep tracking with your Apple Watch to get more accurate. Only Watch data is sent, and only to your pod, for this iPhone's side (\(settings.sideName(for: profile.defaultSide))). Sending again never duplicates anything.")
                .font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 16).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A resend that adds nothing is a success, so it reads as up to date instead of a row of zeros.
    static func podUploadSummary(_ report: PodWatchUpload.Report) -> String {
        let matched = report.matchedStages + report.matchedHeartRate + report.matchedHRV + report.matchedBreathing
        var parts: [String]
        if matched == 0 {
            parts = ["No Apple Watch data found"]
        } else if report.written == 0 {
            parts = ["Up to date"]
        } else {
            parts = ["Added \(report.written.formatted()) new readings"]
        }
        if report.rejectedNights > 0 { parts.append(report.rejectedNights == 1 ? "1 night skipped" : "\(report.rejectedNights) nights skipped") }
        return parts.joined(separator: " · ")
    }

    private var rebuildTitle: String {
        guard let progress = health.rebuildProgress else { return "Rewrite nights" }
        return progress.total == 0 ? "Finding nights…" : "Rewriting \(progress.done) of \(progress.total) nights…"
    }

    private func rebuild() {
        rebuildFailed = false
        Task {
            let rebuilt = await health.rebuild(api: APIBackend.current.createClient(), podID: settings.podID,
                                               side: profile.defaultSide, since: Calendar.current.startOfDay(for: rebuildStart),
                                               demo: APIBackend.current.isDemo)
            rebuildFailed = !rebuilt
            if rebuilt { Haptics.success() } else { Haptics.warning() }
        }
    }

    private var allowButton: some View {
        Button {
            Haptics.light()
            requesting = true
            Task {
                if await health.requestAuthorization() {
                    Haptics.success()
                    if health.preferences.readSleep { await importSchedule() }
                } else {
                    Haptics.warning()
                }
                requesting = false
            }
        } label: {
            BusyLabel(title: "Allow Health access", busyTitle: "Requesting access…", isBusy: requesting)
        }
        .buttonStyle(PrimaryButtonStyle()).disabled(requesting)
    }

    /// iOS shows the Health sheet once; after a refusal the only way back in is the Settings app.
    private var deniedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health access is turned off for sleepypod. Turn it on in Settings under Health, Data Access & Devices.")
                .font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                Haptics.light()
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, 8)
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
