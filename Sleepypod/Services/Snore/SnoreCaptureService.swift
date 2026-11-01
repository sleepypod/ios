import AVFoundation
import Foundation
import Observation
import UIKit

/// Opt-in overnight snore capture. Listens with the iPhone microphone, classifies on this iPhone and
/// saves only snore times, confidence, coverage, interruptions and knock times. No audio is stored or sent.
@MainActor
@Observable
final class SnoreCaptureService {
    enum Status: Equatable {
        case idle, recording, interrupted(String), failed(String)
    }

    private(set) var status: Status = .idle
    /// The session being recorded, kept current for the status view.
    private(set) var current: SnoreSessionDocument?
    /// The most recent finished session, for the morning summary.
    private(set) var lastSession: SnoreSessionDocument?
    private(set) var microphoneDenied = false

    let directory: URL
    private let source: SnoreAudioSource
    private let permission: MicrophonePermission
    private let clock: @Sendable () -> Int64
    private var machine = CaptureMachine()
    private var tracker: SnoreEventTracker?
    private var knocks: KnockWindow?
    private var saveTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var restarting = false
    /// Set while waiting for microphone permission, so a second tap can't start a second tap on bus 0.
    private(set) var starting = false
    /// Set when a session file couldn't be written or excluded from backup.
    private(set) var saveError: String?

    static let detectorVersion = "apple-sound-classifier-v1+hysteresis-0.6-0.4"

    init(directory: URL? = nil,
         source: SnoreAudioSource = MicrophoneSnoreSource(),
         permission: MicrophonePermission = SystemMicrophonePermission(),
         clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
         notifications: NotificationCenter = .default) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snore", isDirectory: true)
        self.source = source
        self.permission = permission
        self.clock = clock
        Self.recoverUnfinished(in: self.directory)
        lastSession = Self.sessions(in: self.directory).first
        observe(notifications)
    }

    var isActive: Bool { machine.isActive }

    /// Starts listening, asking for microphone access first if needed.
    func start() async {
        guard !machine.isActive, !starting else { return }
        starting = true
        defer { starting = false }
        if !permission.isGranted {
            let granted = permission.isDenied ? false : await permission.request()
            guard granted else {
                microphoneDenied = true
                status = .failed("Microphone access is off for sleepypod. Turn it on in Settings to detect snoring.")
                return
            }
        }
        microphoneDenied = false
        let now = clock()
        let id = UUID().uuidString.lowercased()
        let device = UIDevice.current
        var document = SnoreSessionDocument(
            captureId: id, device: device.model, osVersion: "\(device.systemName) \(device.systemVersion)",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            timeZone: TimeZone.current.identifier, startMs: now, detectorVersion: Self.detectorVersion,
            classifier: .init(windowSeconds: 3, overlapFactor: 0.5, onThreshold: 0.6, offThreshold: 0.4))
        let tracker = SnoreEventTracker(captureId: id, detectorVersion: Self.detectorVersion)
        do {
            let format = try startSource()
            document.sampleRate = format.sampleRate
            document.channelCount = format.channelCount
            document.classifier.windowSeconds = format.windowSeconds
            document.classifier.overlapFactor = format.overlapFactor
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        self.tracker = tracker
        knocks = KnockWindow(sessionStartMs: now)
        machine.start(at: now)
        current = document
        status = .recording
        save()
        saveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.save()
            }
        }
    }

    /// Stops listening and keeps the finished session.
    func stop(reason: String = "user") {
        guard machine.isActive else { return }
        source.stop()
        let now = clock()
        machine.stop(at: now)
        finish(at: now, reason: reason)
    }

    /// Deletes a saved session file.
    func delete(_ document: SnoreSessionDocument) {
        try? FileManager.default.removeItem(at: url(for: document.captureId))
        lastSession = Self.sessions(in: directory).first
    }

    func url(for captureId: String) -> URL { directory.appendingPathComponent("snore-\(captureId).json") }

    // MARK: Classifier and knock input

    func handle(_ window: SnoreWindow) {
        guard machine.state == .recording else { return }
        tracker?.add(window)
        current?.events = tracker?.events ?? []
    }

    func handleKnock(_ onsetMs: Int64) {
        guard machine.isActive else { return }
        knocks?.add(onsetMs)
    }

    // MARK: Interruptions

    func interrupt(_ reason: String) {
        guard machine.state == .recording else { return }
        source.stop()
        tracker?.finish()
        machine.interrupt(reason, at: clock())
        status = .interrupted(reason)
        syncCurrent()
        save()
    }

    func resume() {
        guard case .interrupted = machine.state else { return }
        do {
            _ = try startSource()
        } catch {
            let now = clock()
            machine.fail(error.localizedDescription, at: now)
            finish(at: now, reason: "failed: \(error.localizedDescription)")
            status = .failed(error.localizedDescription)
            return
        }
        machine.resume(at: clock())
        status = .recording
        syncCurrent()
    }

    /// Route changes (headphones unplugged, a call's audio route) restart the engine; the gap is recorded.
    func routeChanged() {
        guard machine.state == .recording, !restarting else { return }
        restarting = true
        interrupt("route change")
        resume()
        restarting = false
    }

    /// The app is about to be terminated: save what exists.
    func terminate() { stop(reason: "app terminated") }

    // MARK: Private

    private func startSource() throws -> SnoreAudioFormat {
        try source.start(onWindow: { [weak self] window in
            Task { @MainActor in self?.handle(window) }
        }, onKnock: { [weak self] onset in
            Task { @MainActor in self?.handleKnock(onset) }
        })
    }

    private func finish(at now: Int64, reason: String) {
        saveTask?.cancel()
        saveTask = nil
        tracker?.finish()
        syncCurrent()
        current?.endMs = now
        current?.stopReason = reason
        current?.knocks = knocks?.knocks(endMs: now) ?? []
        save()
        lastSession = current
        current = nil
        tracker = nil
        knocks = nil
        if case .failed = machine.state {} else { status = .idle }
    }

    private func syncCurrent() {
        current?.events = tracker?.events ?? []
        current?.coverage = machine.coverage.intervals
        current?.interruptions = machine.interruptions
    }

    private func save() {
        guard var document = current else { return }
        // A periodic save mid-session records the open coverage span up to now.
        if let open = machine.coverage.openStartMs {
            document.coverage.append(TimeInterval64(startMs: open, endMs: clock()))
        }
        do {
            try Self.prepareDirectory(directory)
            var file = url(for: document.captureId)
            try SnoreSessionDocument.encoder().encode(document).write(to: file, options: .atomic)
            try Self.excludeFromBackup(&file)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            Log.general.error("snore session save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observe(_ center: NotificationCenter) {
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let action = Self.interruptionAction(note.userInfo)
            MainActor.assumeIsolated {
                switch action {
                case .pause: self?.interrupt("audio interruption")
                case .resume: self?.resume()
                case .none: break
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let restart = Self.routeChangeNeedsRestart(note.userInfo)
            MainActor.assumeIsolated { if restart { self?.routeChanged() } }
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminate() }
        })
    }

    /// Only an input device appearing or going away needs a restart. Other reasons, such as the category
    /// change that setting `.record` itself posts, would otherwise loop interrupt-and-restart.
    nonisolated static func routeChangeNeedsRestart(_ userInfo: [AnyHashable: Any]?) -> Bool {
        guard let raw = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return false }
        return reason == .oldDeviceUnavailable || reason == .newDeviceAvailable
    }

    /// Creates the session directory and keeps it out of iCloud and computer backups: nothing here may leave the iPhone.
    nonisolated static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        try excludeFromBackup(&url)
    }

    nonisolated static func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// A session whose file has no end was cut short with the app not running (for example, iOS ended it
    /// overnight). It ends where its last listening span ended.
    nonisolated static func recoverUnfinished(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("snore-") && file.pathExtension == "json" {
            guard var document = try? JSONDecoder().decode(SnoreSessionDocument.self, from: Data(contentsOf: file)),
                  document.endMs == nil else { continue }
            document.endMs = document.coverage.map(\.endMs).max() ?? document.startMs
            document.stopReason = "app not running"
            for index in document.interruptions.indices where document.interruptions[index].endMs == nil {
                document.interruptions[index].endMs = document.endMs
            }
            do {
                try SnoreSessionDocument.encoder().encode(document).write(to: file, options: .atomic)
            } catch {
                Log.general.error("snore session recovery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    enum InterruptionAction: Equatable { case pause, resume, none }

    /// What an `AVAudioSession` interruption notification asks for. An ended interruption without
    /// options resumes; one that says not to resume leaves listening paused.
    nonisolated static func interruptionAction(_ userInfo: [AnyHashable: Any]?) -> InterruptionAction {
        guard let raw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return .none }
        switch type {
        case .began: return .pause
        case .ended:
            let options = (userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            return options?.contains(.shouldResume) ?? true ? .resume : .none
        @unknown default: return .none
        }
    }

    /// Saved sessions, newest first.
    static func sessions(in directory: URL) -> [SnoreSessionDocument] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("snore-") && $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SnoreSessionDocument.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startMs > $1.startMs }
    }
}
