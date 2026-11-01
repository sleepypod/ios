import Foundation
import Observation
import WatchConnectivity

/// Movement recordings received from the Watch, kept on this iPhone under Application Support/WatchMotion.
/// Nothing is uploaded; the user exports a file to the training workspace by hand.
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
        case .success: recordings = inbox.recordings(); lastError = nil
        case .failure(let error): lastError = "A Watch recording could not be read: \(error.localizedDescription)"
        }
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
}
