import Foundation
import Observation
import WatchConnectivity

/// The bed as the iPhone last reported it, and the commands the Watch sends to the pod through the iPhone.
@MainActor
@Observable
final class BedController {
    private static let snapshotKey = "watchBed.snapshot"
    private static let selectionKey = "watchBed.selection"

    enum Selection: String, CaseIterable {
        case left, right, both

        var sides: [WatchBed.Side] {
            switch self {
            case .left: [.left]
            case .right: [.right]
            case .both: [.left, .right]
            }
        }
    }

    private let link: any PhoneLink
    private let defaults: UserDefaults
    private var pendingTarget: Task<Void, Never>?
    private var pendingToken = UUID()
    private(set) var snapshot: WatchBed.Snapshot?
    private(set) var status = ""
    private(set) var failed = false
    private(set) var busy = false
    /// The target the Crown is on, ahead of the pod while a change is waiting to be sent.
    var draftF: Double = Double(WatchBed.baseF)
    private(set) var editing = false
    private var chosen: Selection?

    init(link: any PhoneLink = PhoneSession(), defaults: UserDefaults = .standard) {
        self.link = link
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.snapshotKey) {
            snapshot = try? JSONDecoder().decode(WatchBed.Snapshot.self, from: data)
        }
        chosen = defaults.string(forKey: Self.selectionKey).flatMap(Selection.init(rawValue:))
        syncDraft()
    }

    /// The side picked on this Watch, else the iPhone's own side.
    var selection: Selection {
        get { chosen ?? (snapshot?.defaultSide == .right ? .right : .left) }
        set {
            chosen = newValue
            defaults.set(newValue.rawValue, forKey: Self.selectionKey)
            syncDraft()
        }
    }

    /// The side shown: the selected one, or the left when both are selected.
    var shown: WatchBed.SideState? { snapshot?.state(selection.sides[0]) }

    var title: String {
        switch selection {
        case .both: "Both sides"
        case .left, .right: shown?.name ?? (selection == .left ? "Left" : "Right")
        }
    }

    var isOn: Bool {
        guard let snapshot else { return false }
        return selection.sides.contains { snapshot.state($0)?.isOn == true }
    }

    var unit: WatchBed.Unit { snapshot?.unit ?? .fahrenheit }

    /// The last command's outcome, else what the pod needs.
    var notice: String? {
        if !status.isEmpty { return status }
        if snapshot?.isPriming == true { return "Priming" }
        if snapshot?.waterLow == true { return "Water low: top up the tank" }
        return nil
    }

    func refresh() async {
        await send(.status)
    }

    func togglePower() async {
        await send(.setPower(sides: selection.sides, on: !isOn))
    }

    /// Sends the Crown's target once it stops turning, so one twist is one command.
    func draftChanged() {
        let target = WatchBed.clamp(Int(draftF.rounded()))
        guard target != shown?.targetF else { return }
        editing = true
        let token = UUID()
        pendingToken = token
        pendingTarget?.cancel()
        pendingTarget = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await send(.setTemperature(sides: selection.sides, fahrenheit: target))
            // A later turn owns the draft now.
            guard pendingToken == token else { return }
            editing = false
            syncDraft()
        }
    }

    func stopAlarm() async {
        guard let side = snapshot?.alarmSide else { return }
        await send(.stopAlarm(side: side))
    }

    func snoozeAlarm(minutes: Int = 5) async {
        guard let side = snapshot?.alarmSide else { return }
        await send(.snoozeAlarm(side: side, minutes: minutes))
    }

    /// Asks the iPhone to send the Watch's movement and Health readings to the pod; returns what it said.
    @discardableResult
    func sendNightToPod() async -> String {
        await send(.sendNightToPod)
        return status
    }

    private func send(_ request: WatchBed.Request) async {
        busy = true
        defer { busy = false }
        do {
            let reply = try await link.send(request)
            if let snapshot = reply.snapshot {
                self.snapshot = snapshot
                if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.snapshotKey) }
            }
            status = reply.message ?? ""
            failed = reply.failed
        } catch {
            status = (error as? PhoneLinkError)?.message ?? "Couldn't reach iPhone."
            failed = true
        }
        if !editing { syncDraft() }
    }

    private func syncDraft() {
        if let target = shown?.targetF { draftF = Double(target) }
    }
}

enum PhoneLinkError: Error {
    case unreachable

    var message: String {
        switch self {
        case .unreachable: "iPhone isn't in reach."
        }
    }
}

protocol PhoneLink: Sendable {
    func send(_ request: WatchBed.Request) async throws -> WatchBed.Reply
}

/// Sends a request to the iPhone app, which WatchConnectivity wakes in the background if needed.
struct PhoneSession: PhoneLink {
    func send(_ request: WatchBed.Request) async throws -> WatchBed.Reply {
        let session = WCSession.default
        // The recorder activates the session at launch; a request in the first moment waits for it.
        for _ in 0..<20 where session.activationState != .activated {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard session.activationState == .activated, session.isReachable else { throw PhoneLinkError.unreachable }
        let message = try WatchBed.message(request)
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                continuation.resume(with: Result { try WatchBed.decode(WatchBed.Reply.self, from: reply) })
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }
}
