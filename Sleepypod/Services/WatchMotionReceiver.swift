import Foundation
import Observation
import WatchConnectivity

/// Movement recordings received from the Watch, kept on this iPhone under Application Support/WatchMotion.
/// The receiver sends each to the user's own pod; nothing goes anywhere else.
struct WatchMotionInbox: Sendable {
    let directory: URL

    static var standard: WatchMotionInbox {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return WatchMotionInbox(directory: base.appendingPathComponent("WatchMotion", isDirectory: true))
    }

    struct Recording: Identifiable, Sendable, Equatable {
        var url: URL
        var from: Date
        var to: Date
        var bins: Int
        var id: URL { url }
    }

    /// Validates an incoming file and stores it under its canonical name; a repeat delivery replaces the copy.
    @discardableResult
    func store(contentsOf source: URL) throws -> Recording {
        let data = try Data(contentsOf: source)
        let file = try WatchMotionFile.decode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(file.fileName)
        try data.write(to: destination, options: .atomic)
        return Self.recording(file, at: destination)
    }

    /// Valid recordings, newest first. Unreadable files are skipped rather than shown.
    func recordings() -> [Recording] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let file = try? WatchMotionFile.decode(data) else { return nil }
                return Self.recording(file, at: url)
            }
            .sorted { $0.from > $1.from }
    }

    private static func recording(_ file: WatchMotionFile, at url: URL) -> Recording {
        Recording(url: url, from: Date(timeIntervalSince1970: Double(file.recordedFromMs) / 1000),
                  to: Date(timeIntervalSince1970: Double(file.recordedToMs) / 1000), bins: file.bins.count)
    }
}

@MainActor
@Observable
final class WatchMotionReceiver: NSObject {
    private(set) var recordings: [WatchMotionInbox.Recording] = []
    private(set) var lastError: String?
    nonisolated let inbox: WatchMotionInbox
    /// The pod to send recordings to and the side they belong to; nil when the backend can't store them.
    var podDestination: @MainActor () -> (api: SleepypodProtocol, side: Side)? = { nil }
    /// What the pod said about each recording this session.
    private(set) var podUploads: [URL: WatchMotionPodUpload.Outcome] = [:]
    private(set) var sendingToPod: Set<URL> = []
    /// Set when the pod's software predates the route, so arriving recordings wait for a manual send.
    private(set) var podLacksSupport = false
    /// Answers the Watch's bed requests. Set at launch, before `activate`, so a background wake can answer.
    var bedRequests: ((WatchBed.Request) async -> WatchBed.Reply)?

    init(inbox: WatchMotionInbox = .standard) {
        self.inbox = inbox
        super.init()
        recordings = inbox.recordings()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func received(_ result: Result<WatchMotionInbox.Recording, Error>) {
        switch result {
        case .success(let recording):
            recordings = inbox.recordings()
            lastError = nil
            if !podLacksSupport { Task { await sendToPod([recording]) } }
        case .failure(let error): lastError = "A Watch recording could not be read: \(error.localizedDescription)"
        }
    }

    var canSendToPod: Bool { podDestination() != nil }

    /// Sends recordings one at a time; resending is safe because the pod keys them by side and start.
    func sendToPod(_ recordings: [WatchMotionInbox.Recording]) async {
        guard let destination = podDestination() else { return }
        for recording in recordings where !sendingToPod.contains(recording.url) {
            sendingToPod.insert(recording.url)
            let outcome = await WatchMotionPodUpload.send(contentsOf: recording.url, side: destination.side, api: destination.api)
            sendingToPod.remove(recording.url)
            podUploads[recording.url] = outcome
            podLacksSupport = outcome == .unsupported
            if podLacksSupport { break }
        }
    }

    /// Sends the recordings from the last `days` again and returns what the pod said about each.
    func sendRecent(days: Int = 2, now: Date = .now) async -> [WatchMotionPodUpload.Outcome] {
        let recent = recordings.filter { $0.to > now.addingTimeInterval(-Double(days) * 86400) }
        await sendToPod(recent)
        return recent.compactMap { podUploads[$0.url] }
    }
}

extension WatchMotionReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    /// The transferred file is deleted when this returns, so it is copied before hopping to the main actor.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let result = Result { try inbox.store(contentsOf: file.fileURL) }
        Task { @MainActor in self.received(result) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let request = Result { try WatchBed.decode(WatchBed.Request.self, from: message) }
        let reply = WatchReply(send: replyHandler)
        Task { @MainActor in
            let answer: WatchBed.Reply
            switch request {
            case .success(let request):
                answer = await self.bedRequests?(request) ?? WatchBed.Reply(message: "Open sleepypod on iPhone.", failed: true)
            case .failure:
                answer = WatchBed.Reply(message: "Update sleepypod on iPhone.", failed: true)
            }
            reply.send((try? WatchBed.message(answer)) ?? [:])
        }
    }
}

/// WatchConnectivity calls the reply handler from any thread; it is only called once, with plain data.
private struct WatchReply: @unchecked Sendable {
    let send: ([String: Any]) -> Void
}
