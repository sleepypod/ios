import SwiftUI

/// Opt-in snore detection: explainer, Start/Stop, live status and the last session's summary.
struct SnoreCaptureView: View {
    @Environment(SnoreCaptureService.self) private var snore
    @Environment(\.openURL) private var openURL
    @State private var shareURL: URL?
    @State private var confirmDelete = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "waveform.badge.mic").font(.system(size: 24)).foregroundStyle(Theme.text1)
                        .frame(width: 56, height: 56)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.border2, lineWidth: 1))
                        .accessibilityHidden(true)
                    Text("Snore detection").font(.system(size: titleSize, weight: .bold)).tracking(-0.5)
                    Text("Listens for snoring through this iPhone's microphone while you sleep, using Apple's built-in sound classifier on this iPhone.")
                        .font(.subheadline).foregroundStyle(Theme.text2).lineSpacing(3)
                    Text("Audio is never recorded, saved or uploaded. sleepypod keeps only when snoring was detected, how confident the classifier was, and when the microphone was listening.")
                        .font(.footnote).foregroundStyle(Theme.text2).lineSpacing(3)
                    Text("Put the iPhone on your nightstand, plugged in, with sleepypod open. After starting and before stopping, knock three times on the bed frame so the night lines up with the pod.")
                        .font(.footnote).foregroundStyle(Theme.text2).lineSpacing(3)
                }
                .padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 16) {
                    GroupedSection("TONIGHT") {
                        GroupedCard {
                            SettingsRow("Status") { RowValue(statusText) }
                            if let current = snore.current {
                                SettingsRow("Snores detected") { RowValue("\(current.events.count)") }
                            }
                        }
                    }
                    controlButton
                    if snore.microphoneDenied { deniedNote }
                    if case .failed(let message) = snore.status, !snore.microphoneDenied {
                        Text(message).font(.footnote).foregroundStyle(Theme.amber).padding(.horizontal, 16)
                    }
                    if let last = snore.lastSession, last.endMs != nil { summary(last) }
                    Text("Beta. Detection quality in a real bedroom and overnight battery use aren't measured yet. Snoring isn't a diagnosis of anything.")
                        .font(.footnote).foregroundStyle(Theme.text3).padding(.horizontal, 16)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background).tint(Theme.green)
        .navigationTitle("Snore detection").navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let last = snore.lastSession { snore.delete(last) } }
        }
    }

    private var statusText: String {
        switch snore.status {
        case .idle: "Off"
        case .recording: "Listening"
        case .interrupted(let reason): "Paused (\(reason))"
        case .failed: "Couldn't start"
        }
    }

    private var controlButton: some View {
        Button(snore.isActive ? "Stop" : "Start listening") {
            Haptics.light()
            if snore.isActive { snore.stop() } else { Task { await snore.start() } }
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private var deniedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Microphone access is off for sleepypod. Turn it on in Settings to detect snoring.")
                .font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func summary(_ session: SnoreSessionDocument) -> some View {
        GroupedSection("LAST SESSION") {
            GroupedCard {
                SettingsRow("Listened") { RowValue(Self.duration(session.coveredMs)) }
                SettingsRow("Snoring detected") { RowValue(Self.duration(session.snoreMs)) }
                SettingsRow("Snore events") { RowValue("\(session.events.count)") }
                SettingsRow("Longest") { RowValue(Self.duration(session.longestEventMs)) }
                SettingsRow("Interruptions") { RowValue("\(session.interruptions.count)") }
                SettingsRow("Knocks for pod sync") { RowValue("\(session.knocks.count)") }
                Button { shareURL = snore.url(for: session.captureId) } label: {
                    SettingsRow("Export for training", icon: "square.and.arrow.up", chevron: true)
                }
                Button { confirmDelete = true } label: {
                    SettingsRow("Delete session", icon: "trash", iconColor: Theme.red)
                }
            }
        }
    }

    static func duration(_ ms: Int64) -> String {
        let minutes = Int(ms / 60_000)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}
