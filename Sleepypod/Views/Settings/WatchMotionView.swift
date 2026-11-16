import SwiftUI

/// Overnight movement recordings sent from the sleepypod Watch app. Each is sent to the pod as it arrives, opens
/// against the pod's movement for the same night and can be shared to a computer for the training workspace.
struct WatchMotionView: View {
    @Environment(WatchMotionReceiver.self) private var receiver
    @Environment(UserProfile.self) private var profile
    @Environment(SettingsManager.self) private var settings
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var shown = Self.page
    /// Recordings listed at first and added by each Show older, so a long history doesn't scroll forever.
    private static let page = 7

    var body: some View {
        @Bindable var receiver = receiver
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(receiver.nightlyEnabled
                     ? "The sleepypod Watch app records every night around your usual sleep and sends it here in the morning. Open one to compare it with the pod's movement, or share it to a computer to use as movement labels in the training workspace."
                     : "Start a recording on the Watch at bedtime. In the morning, send it from the Watch and it appears here. Open one to compare it with the pod's movement, or share it to a computer to use as movement labels in the training workspace.")
                    .font(.footnote).foregroundStyle(Theme.text2).lineSpacing(3)
                    .padding(.horizontal, 8)
                GroupedSection("NIGHTLY") {
                    GroupedCard {
                        SettingsRow("Record every night", subtitle: nightlySubtitle, height: 56) {
                            Toggle("Record every night", isOn: $receiver.nightlyEnabled).labelsHidden()
                        }
                    }
                }
                if let error = receiver.lastError {
                    Text(error).font(.footnote).foregroundStyle(Theme.red).padding(.horizontal, 8)
                }
                GroupedSection("RECORDINGS") {
                    GroupedCard {
                        if receiver.recordings.isEmpty {
                            SettingsRow("No recordings yet", subtitle: "Recordings from the Watch appear here")
                        }
                        ForEach(receiver.recordings.prefix(shown)) { recording in
                            NavigationLink { WatchMotionNightView(recording: recording) } label: {
                                SettingsRow(recording.from.formatted(date: .abbreviated, time: .shortened),
                                            subtitle: subtitle(recording),
                                            icon: "figure.walk", iconColor: Theme.text1, chevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                        if receiver.recordings.count > shown {
                            Button {
                                Haptics.tap()
                                shown += Self.page
                            } label: {
                                SettingsRow("Show older", subtitle: "\(receiver.recordings.count - shown) more",
                                            icon: "clock.arrow.circlepath", iconColor: Theme.text1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !receiver.recordings.isEmpty {
                    actionsSection
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Watch movement")
        .sheet(item: Binding(get: { exportURL.map(ExportItem.init) }, set: { exportURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
    }

    private func exportAll() {
        Haptics.light()
        do {
            exportURL = try receiver.inbox.combinedExport()
            exportError = nil
        } catch {
            exportError = "Couldn't combine the recordings: \(error.localizedDescription)"
        }
    }

    private var actionsSection: some View {
        GroupedSection("ACTIONS") {
            GroupedCard {
                if receiver.canSendToPod { sendAllButton }
                Button(action: exportAll) {
                    SettingsRow("Export all", subtitle: "\(receiver.recordings.count) recordings in one file",
                                icon: "square.and.arrow.up", iconColor: Theme.text1, chevron: true)
                }
                .buttonStyle(.plain)
            }
            if let exportError {
                Text(exportError).font(.footnote).foregroundStyle(Theme.red).padding(.horizontal, 16)
            }
            if receiver.canSendToPod {
                podNotes
                GroupedCard { resendAllButton }
            }
        }
    }

    private var unsent: [WatchMotionInbox.Recording] { receiver.unsent(side: profile.defaultSide) }

    private var sendAllButton: some View {
        Button { send(unsent, force: false) } label: {
            SettingsRow(receiver.sendingToPod.isEmpty ? "Send new to pod" : "Sending…",
                        subtitle: unsent.isEmpty ? "Every recording is on the pod" : "\(unsent.count) not on the pod yet",
                        icon: "arrow.up.circle") {
                if !receiver.sendingToPod.isEmpty { ProgressView() }
            }
        }
        .buttonStyle(.plain)
        .disabled(!receiver.sendingToPod.isEmpty || unsent.isEmpty)
    }

    /// Sends everything again, including recordings the pod already has, for a pod that was reset or replaced.
    private var resendAllButton: some View {
        Button { send(receiver.recordings, force: true) } label: {
            SettingsRow("Send all again", subtitle: "Includes recordings already on the pod", icon: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .disabled(!receiver.sendingToPod.isEmpty)
    }

    private func send(_ recordings: [WatchMotionInbox.Recording], force: Bool) {
        Haptics.light()
        Task {
            await receiver.sendToPod(recordings, force: force)
            let outcomes = recordings.map { receiver.podUploads[$0.url] }
            if outcomes.allSatisfy({ if case .stored = $0 { true } else { false } }) { Haptics.success() } else { Haptics.warning() }
        }
    }

    @ViewBuilder private var podNotes: some View {
        if receiver.podLacksSupport {
            Text("This pod's software doesn't store Watch movement yet. Update the pod, then send again.")
                .font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 16)
        }
        ForEach(failures, id: \.self) { message in
            Text(message).font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 16)
        }
        Text("Each recording goes to your pod when it arrives, for this iPhone's side (\(settings.sideName(for: profile.defaultSide))), and nowhere else. Sending again never duplicates anything.")
            .font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 16).fixedSize(horizontal: false, vertical: true)
    }

    /// Distinct failure messages from the last attempts, so a dead pod reads as one line, not one per night.
    private var failures: [String] {
        var seen: [String] = []
        for recording in receiver.recordings {
            if case .failed(let message) = receiver.podUploads[recording.url], !seen.contains(message) { seen.append(message) }
        }
        return seen
    }

    private var nightlySubtitle: String {
        let night = receiver.nightly
        let day = Calendar.current.startOfDay(for: .now)
        func clock(_ minutes: Int) -> String {
            day.addingTimeInterval(Double(minutes) * 60).formatted(date: .omitted, time: .shortened)
        }
        let source = night.fromHealth ? "from Watch sleep in Health" : "until Health has a night"
        return "Around \(clock(night.bedMinutes))–\(clock(night.wakeMinutes)), \(source)"
    }

    private func subtitle(_ recording: WatchMotionInbox.Recording) -> String {
        let duration = Duration.seconds(recording.to.timeIntervalSince(recording.from))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        let pod = WatchMotionPodUpload.summary(receiver.podUploads[recording.url], sending: receiver.sendingToPod.contains(recording.url))
            ?? (receiver.isOnPod(recording, side: profile.defaultSide) ? "On pod" : nil)
        return (["\(duration)", "\(recording.bins.formatted()) bins"] + [recording.capture?.summary, pod].compactMap { $0 }).joined(separator: " · ")
    }
}

private struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.path }
}
