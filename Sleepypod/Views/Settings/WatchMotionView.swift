import SwiftUI

/// Overnight movement recordings sent from the sleepypod Watch app. Each can be shared to a computer for the
/// training workspace; nothing is uploaded automatically.
struct WatchMotionView: View {
    @Environment(WatchMotionReceiver.self) private var receiver

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Start a recording on the Watch at bedtime. In the morning, send it from the Watch and it appears here. Share a file to a computer to use it as movement labels in the training workspace.")
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
                            ShareLink(item: recording.url) {
                                SettingsRow(recording.from.formatted(date: .abbreviated, time: .shortened),
                                            subtitle: "\(Duration.seconds(recording.to.timeIntervalSince(recording.from)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) · \(recording.bins) bins",
                                            icon: "square.and.arrow.up", iconColor: Theme.text1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Watch movement")
    }
}
