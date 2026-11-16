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
        /// How the Watch says the night went, including battery; nil for files sent before it said.
        var capture: WatchMotionCapture?
        var id: URL { url }
    }

    /// Capture notes sit apart from the recordings, so the files themselves and Export all stay as the Watch wrote them.
    private var capturesDirectory: URL { directory.appendingPathComponent("captures", isDirectory: true) }

    /// Validates an incoming file and stores it under its canonical name; a repeat delivery replaces the copy.
    @discardableResult
    func store(contentsOf source: URL, capture: WatchMotionCapture? = nil) throws -> Recording {
        let data = try Data(contentsOf: source)
        let file = try WatchMotionFile.decode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(file.fileName)
        try data.write(to: destination, options: .atomic)
        if let capture, capture.recordedFromMs == file.recordedFromMs {
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(capture).write(to: capturesDirectory.appendingPathComponent(file.fileName), options: .atomic)
        }
        return recording(file, at: destination)
    }

    /// Valid recordings, newest first. Unreadable files are skipped rather than shown.
    func recordings() -> [Recording] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let file = try? WatchMotionFile.decode(data) else { return nil }
                return recording(file, at: url)
            }
            .sorted { $0.from > $1.from }
    }

    /// Every recording in one JSON array, oldest first, each exactly as the Watch sent it, for the training workspace.
    func combinedExport(in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let all = recordings().sorted { $0.from < $1.from }
        guard let first = all.first, let last = all.last else { throw CocoaError(.fileNoSuchFile) }
        var data = Data("[".utf8)
        for (index, recording) in all.enumerated() {
            if index > 0 { data.append(Data(",\n".utf8)) }
            data.append(try Data(contentsOf: recording.url))
        }
        data.append(Data("]\n".utf8))
        let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.omitted)
        let url = directory.appendingPathComponent("watch-motion-all-\(first.from.formatted(day))-\(last.to.formatted(day)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func recording(_ file: WatchMotionFile, at url: URL) -> Recording {
        let capture = (try? Data(contentsOf: capturesDirectory.appendingPathComponent(file.fileName)))
            .flatMap { try? JSONDecoder().decode(WatchMotionCapture.self, from: $0) }
        return Recording(url: url, from: Date(timeIntervalSince1970: Double(file.recordedFromMs) / 1000),
                         to: Date(timeIntervalSince1970: Double(file.recordedToMs) / 1000), bins: file.bins.count, capture: capture)
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
    /// Whether the Watch records every night, and the night it records, as last sent to it.
    private(set) var nightly: NightlyMotionSettings
    private let defaults: UserDefaults
    private static let nightlyKey = "watchMotion.nightly"
    /// Recordings the pod stored, by side and file name, with the file's modification time when it was sent. Kept
    /// across launches so a send skips them; a redelivered file is rewritten with a new time and goes again.
    private var sentToPod: [String: Double]
    private static let sentKey = "watchMotion.sentToPod"
    /// Shortest Health night taken as the usual one, so a nap doesn't move it.
    static let minimumNight: TimeInterval = 3 * 3600

    init(inbox: WatchMotionInbox = .standard, defaults: UserDefaults = .standard) {
        self.inbox = inbox
        self.defaults = defaults
        nightly = defaults.data(forKey: Self.nightlyKey).flatMap { try? JSONDecoder().decode(NightlyMotionSettings.self, from: $0) }
            ?? NightlyMotionSettings()
        sentToPod = defaults.dictionary(forKey: Self.sentKey) as? [String: Double] ?? [:]
        super.init()
        recordings = inbox.recordings()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// On by default; off, the Watch records only when started from it.
    var nightlyEnabled: Bool {
        get { nightly.enabled }
        set { setNightly { $0.enabled = newValue } }
    }

    /// Takes the usual night from last night's Watch sleep in Health; without one the last known night stays.
    func updateNightly(bed: Date?, wake: Date?) {
        guard let bed, let wake, wake.timeIntervalSince(bed) >= Self.minimumNight else {
            pushNightly()
            return
        }
        setNightly { $0 = NightlyMotionSettings(enabled: $0.enabled, bed: bed, wake: wake) }
    }

    private func setNightly(_ change: (inout NightlyMotionSettings) -> Void) {
        change(&nightly)
        if let data = try? JSONEncoder().encode(nightly) { defaults.set(data, forKey: Self.nightlyKey) }
        pushNightly()
    }

    /// The application context keeps only the latest value and reaches the Watch whenever it next wakes.
    func pushNightly() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(nightly.context())
        } catch {
            Log.general.error("Nightly Watch movement settings not sent: \(error.localizedDescription, privacy: .public)")
        }
    }

    func received(_ result: Result<WatchMotionInbox.Recording, Error>) {
        switch result {
        case .success(let recording):
            recordings = inbox.recordings()
            lastError = nil
            if let capture = recording.capture {
                Log.general.notice("Watch movement night received: \(recording.bins) bins, \(capture.summary, privacy: .public)")
            }
            if !podLacksSupport { Task { await sendToPod([recording]) } }
        case .failure(let error): lastError = "A Watch recording could not be read: \(error.localizedDescription)"
        }
    }

    var canSendToPod: Bool { podDestination() != nil }

    /// Whether the pod already stored this recording, as it is now, for `side`.
    func isOnPod(_ recording: WatchMotionInbox.Recording, side: Side) -> Bool {
        guard let sent = sentToPod[Self.sentKey(recording, side: side)] else { return false }
        return sent == Self.modified(recording.url)
    }

    /// The recordings `side` hasn't stored yet.
    func unsent(side: Side) -> [WatchMotionInbox.Recording] {
        recordings.filter { !isOnPod($0, side: side) }
    }

    /// Sends recordings one at a time, skipping those the pod already stored unless `force` is set. Resending is
    /// safe either way because the pod keys them by side and start.
    func sendToPod(_ recordings: [WatchMotionInbox.Recording], force: Bool = false) async {
        guard let destination = podDestination() else { return }
        for recording in recordings where !sendingToPod.contains(recording.url) {
            if !force && isOnPod(recording, side: destination.side) { continue }
            sendingToPod.insert(recording.url)
            let outcome = await WatchMotionPodUpload.send(contentsOf: recording.url, side: destination.side, api: destination.api)
            sendingToPod.remove(recording.url)
            podUploads[recording.url] = outcome
            if case .stored = outcome, let modified = Self.modified(recording.url) {
                sentToPod[Self.sentKey(recording, side: destination.side)] = modified
                defaults.set(sentToPod, forKey: Self.sentKey)
            }
            podLacksSupport = outcome == .unsupported
            if podLacksSupport { break }
        }
    }

    private static func sentKey(_ recording: WatchMotionInbox.Recording, side: Side) -> String {
        "\(side.rawValue)/\(recording.url.lastPathComponent)"
    }

    /// Read from the file system each time: URL resource values are cached per URL and would miss a rewrite.
    private static func modified(_ url: URL) -> Double? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)?.timeIntervalSince1970
    }

    /// Sends the recordings from the last `days` the pod doesn't have yet and returns what it said about each.
    func sendRecent(days: Int = 2, now: Date = .now) async -> [WatchMotionPodUpload.Outcome] {
        let recent = recordings.filter { $0.to > now.addingTimeInterval(-Double(days) * 86400) }
        let destination = podDestination()
        let unsent = recent.filter { recording in destination.map { !isOnPod(recording, side: $0.side) } ?? true }
        await sendToPod(unsent)
        return unsent.compactMap { podUploads[$0.url] }
    }
}

extension WatchMotionReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushNightly() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushNightly() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    /// The transferred file is deleted when this returns, so it is copied before hopping to the main actor.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let capture = WatchMotionCapture.decode(metadata: file.metadata)
        let result = Result { try inbox.store(contentsOf: file.fileURL, capture: capture) }
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
