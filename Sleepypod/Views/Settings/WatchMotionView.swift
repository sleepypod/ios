import SwiftUI

/// Overnight movement recordings sent from the sleepypod Watch app. Each is sent to the pod as it arrives, opens
/// against the pod's movement for the same night and can be shared to a computer for the training workspace.
struct WatchMotionView: View {
    @Environment(WatchMotionReceiver.self) private var receiver
    @Environment(UserProfile.self) private var profile
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Start a recording on the Watch at bedtime. In the morning, send it from the Watch and it appears here. Open one to compare it with the pod's movement, or share it to a computer to use as movement labels in the training workspace.")
                    .font(.footnote).foregroundStyle(Theme.text2).lineSpacing(3)
                    .padding(.horizontal, 8)
                if let error = receiver.lastError {
                    Text(error).font(.footnote).foregroundStyle(Theme.red).padding(.horizontal, 8)
                }
                GroupedSection("RECORDINGS") {
                    GroupedCard {
                        if receiver.recordings.isEmpty {
                            SettingsRow("No recordings yet", subtitle: "Recordings from the Watch appear here")
                        }
                        ForEach(receiver.recordings) { recording in
                            NavigationLink { WatchMotionNightView(recording: recording) } label: {
                                SettingsRow(recording.from.formatted(date: .abbreviated, time: .shortened),
                                            subtitle: subtitle(recording),
                                            icon: "figure.walk", iconColor: Theme.text1, chevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if receiver.canSendToPod && !receiver.recordings.isEmpty {
                    podSection
                }
            }
            .padding(16)
        }
        .navigationTitle("Watch movement")
    }

    private var podSection: some View {
        GroupedSection("SEND TO POD") {
            GroupedCard {
                Button {
                    Haptics.light()
                    Task {
                        await receiver.sendToPod(receiver.recordings)
                        let outcomes = receiver.recordings.map { receiver.podUploads[$0.url] }
                        if outcomes.allSatisfy({ if case .stored = $0 { true } else { false } }) { Haptics.success() } else { Haptics.warning() }
                    }
                } label: {
                    SettingsRow(receiver.sendingToPod.isEmpty ? "Send all to pod" : "Sending…", icon: "arrow.up.circle") {
                        if !receiver.sendingToPod.isEmpty { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!receiver.sendingToPod.isEmpty)
            }
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
    }

    /// Distinct failure messages from the last attempts, so a dead pod reads as one line, not one per night.
    private var failures: [String] {
        var seen: [String] = []
        for recording in receiver.recordings {
            if case .failed(let message) = receiver.podUploads[recording.url], !seen.contains(message) { seen.append(message) }
        }
        return seen
    }

    private func subtitle(_ recording: WatchMotionInbox.Recording) -> String {
        let duration = Duration.seconds(recording.to.timeIntervalSince(recording.from))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        let pod = WatchMotionPodUpload.summary(receiver.podUploads[recording.url], sending: receiver.sendingToPod.contains(recording.url))
        return (["\(duration)", "\(recording.bins) bins"] + [pod].compactMap { $0 }).joined(separator: " · ")
    }
}
