import Foundation

/// Carries out the Watch's bed requests against the pod and answers with the pod's state, so the Watch can work
/// the bed through this iPhone's connection. Wired at launch: the Watch can wake the app in the background.
@MainActor
final class WatchBedRelay {
    struct Context {
        var api: SleepypodProtocol
        var defaultSide: Side
        var unit: TemperatureFormat
        var sideName: (Side) -> String
    }

    /// The pod to talk to, or nil before one is set up.
    var context: () -> Context? = { nil }
    /// Each status read for the Watch, so the iPhone's screens follow what the Watch changed.
    var onStatus: (DeviceStatus) -> Void = { _ in }
    /// Sends the Watch's recordings and Health readings to the pod and says what happened.
    var sendNight: () async -> String = { "This pod can't store Watch data." }

    func handle(_ request: WatchBed.Request) async -> WatchBed.Reply {
        guard let context = context() else {
            return WatchBed.Reply(message: "Set up your pod on iPhone first.", failed: true)
        }
        let api = context.api
        var note: String?
        do {
            switch request {
            case .status:
                break
            case .setPower(let sides, let on):
                try await api.updateDeviceStatus(Self.update(sides, SideStatusUpdate(targetTemperatureF: nil, isOn: on)))
            case .setTemperature(let sides, let fahrenheit):
                let update = SideStatusUpdate(targetTemperatureF: WatchBed.clamp(fahrenheit), isOn: nil)
                try await api.updateDeviceStatus(Self.update(sides, update))
            case .stopAlarm(let side):
                try await api.clearAlarm(side: Side(side))
            case .snoozeAlarm(let side, let minutes):
                let snooze = try await api.snoozeAlarm(side: Side(side), duration: minutes * 60)
                note = "Snoozed until \(snooze.snoozeUntilDate.formatted(date: .omitted, time: .shortened))"
            case .sendNightToPod:
                note = await sendNight()
            }
        } catch {
            return WatchBed.Reply(message: "The pod didn't take it: \(error.localizedDescription)", failed: true)
        }
        do {
            // The pod reports a command a moment after taking it, so the answer shows what was asked for.
            let status = Self.applying(request, to: try await api.getDeviceStatus())
            onStatus(status)
            return WatchBed.Reply(snapshot: Self.snapshot(status, context: context), message: note)
        } catch {
            return WatchBed.Reply(message: note ?? "Couldn't reach the pod.", failed: note == nil)
        }
    }

    static func update(_ sides: [WatchBed.Side], _ change: SideStatusUpdate) -> DeviceStatusUpdate {
        DeviceStatusUpdate(left: sides.contains(.left) ? change : nil, right: sides.contains(.right) ? change : nil)
    }

    static func applying(_ request: WatchBed.Request, to status: DeviceStatus) -> DeviceStatus {
        var status = status
        func change(_ sides: [WatchBed.Side], _ body: (inout SideStatus) -> Void) {
            if sides.contains(.left) { body(&status.left) }
            if sides.contains(.right) { body(&status.right) }
        }
        switch request {
        case .setPower(let sides, let on): change(sides) { $0.isOn = on }
        case .setTemperature(let sides, let fahrenheit): change(sides) { $0.targetTemperatureF = WatchBed.clamp(fahrenheit) }
        case .stopAlarm(let side), .snoozeAlarm(let side, _): change([side]) { $0.isAlarmVibrating = false }
        case .status, .sendNightToPod: break
        }
        return status
    }

    static func snapshot(_ status: DeviceStatus, context: Context, now: Date = .now) -> WatchBed.Snapshot {
        let sides = Side.allCases.map { side in
            let state = status.status(for: side)
            return WatchBed.SideState(side: WatchBed.Side(side), name: context.sideName(side), isOn: state.isOn,
                                      currentF: state.currentTemperatureF, targetF: state.targetTemperatureF,
                                      isAlarmVibrating: state.isAlarmVibrating)
        }
        return WatchBed.Snapshot(sides: sides, defaultSide: WatchBed.Side(context.defaultSide), unit: WatchBed.Unit(context.unit),
                                 waterLow: status.waterLevel.lowercased() == "low", isPriming: status.isPriming, takenAt: now)
    }

    /// One line for the Watch about a send: what was new, and why anything was left out.
    static func nightSummary(motion: [WatchMotionPodUpload.Outcome], health: PodWatchUpload.Report?, healthProblem: String?) -> String {
        var sent: [String] = []
        let newNights = motion.filter { if case .stored(let result) = $0 { result.status != .unchanged } else { false } }.count
        if newNights > 0 { sent.append(newNights == 1 ? "1 movement night" : "\(newNights) movement nights") }
        if let health, health.written > 0 { sent.append("\(health.written.formatted()) Health readings") }
        var problems: [String] = []
        if motion.contains(.unsupported) {
            problems.append("Update the pod to store movement")
        } else if motion.contains(where: { if case .failed = $0 { true } else { false } }) {
            problems.append("Some movement wasn't sent")
        }
        if let healthProblem { problems.append(healthProblem) }
        let lead = sent.isEmpty ? (problems.isEmpty ? ["Already on the pod"] : []) : ["Sent " + sent.joined(separator: " and ")]
        return (lead + problems).joined(separator: ". ")
    }
}

extension WatchBed.Side {
    init(_ side: Side) { self = side == .left ? .left : .right }
}

extension Side {
    init(_ side: WatchBed.Side) { self = side == .left ? .left : .right }
}

extension WatchBed.Unit {
    init(_ format: TemperatureFormat) {
        switch format {
        case .fahrenheit: self = .fahrenheit
        case .celsius: self = .celsius
        case .relative: self = .relative
        }
    }
}
