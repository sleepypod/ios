import Foundation
import Testing
@testable import Sleepypod

/// Records what the relay asked of the pod and answers status from the demo pod.
private final class RecordingPod: MockAPIClient, @unchecked Sendable {
    var updates: [DeviceStatusUpdate] = []
    var cleared: [Side] = []
    var snoozed: [(Side, Int)] = []
    var status: DeviceStatus?
    var failUpdate = false

    override func getDeviceStatus() async throws -> DeviceStatus {
        guard let status else { throw APIError.noBaseURL }
        return status
    }
    override func updateDeviceStatus(_ update: DeviceStatusUpdate) async throws {
        if failUpdate { throw APIError.serverError(message: "busy") }
        updates.append(update)
    }
    override func clearAlarm(side: Side) async throws { cleared.append(side) }
    override func snoozeAlarm(side: Side, duration: Int) async throws -> SnoozeResponse {
        snoozed.append((side, duration))
        return SnoozeResponse(success: true, snoozeUntil: 1_800_000_000 + duration)
    }
}

@MainActor
struct WatchBedRelayTests {
    private func relay(_ pod: RecordingPod, unit: TemperatureFormat = .fahrenheit) -> WatchBedRelay {
        let relay = WatchBedRelay()
        relay.context = {
            WatchBedRelay.Context(api: pod, defaultSide: .right, unit: unit, sideName: { $0 == .left ? "Alex" : "Sam" })
        }
        return relay
    }

    private func pod() async throws -> RecordingPod {
        let pod = RecordingPod()
        pod.status = try await MockClient().getDeviceStatus()
        return pod
    }

    @Test func powerGoesOnlyToTheChosenSidesAndTheAnswerShowsIt() async throws {
        let pod = try await pod()
        let reply = await relay(pod).handle(.setPower(sides: [.left], on: false))
        #expect(pod.updates.count == 1)
        #expect(pod.updates[0].left?.isOn == false)
        #expect(pod.updates[0].right == nil)
        #expect(reply.failed == false)
        #expect(reply.snapshot?.state(.left)?.isOn == false)
        #expect(reply.snapshot?.state(.right)?.isOn == true)
    }

    @Test func temperatureIsClampedAndSentToBothSides() async throws {
        let pod = try await pod()
        let reply = await relay(pod).handle(.setTemperature(sides: [.left, .right], fahrenheit: 140))
        #expect(pod.updates[0].left?.targetTemperatureF == 110)
        #expect(pod.updates[0].right?.targetTemperatureF == 110)
        #expect(pod.updates[0].left?.isOn == nil)
        #expect(reply.snapshot?.state(.right)?.targetF == 110)
    }

    @Test func snapshotCarriesNamesUnitAndTheIPhonesSide() async throws {
        let pod = try await pod()
        pod.status?.waterLevel = "low"
        let reply = await relay(pod, unit: .celsius).handle(.status)
        #expect(pod.updates.isEmpty)
        #expect(reply.snapshot?.state(.left)?.name == "Alex")
        #expect(reply.snapshot?.state(.right)?.name == "Sam")
        #expect(reply.snapshot?.unit == .celsius)
        #expect(reply.snapshot?.defaultSide == .right)
        #expect(reply.snapshot?.waterLow == true)
    }

    @Test func alarmStopAndSnoozeReachTheVibratingSide() async throws {
        let pod = try await pod()
        pod.status?.right.isAlarmVibrating = true
        let stopped = await relay(pod).handle(.stopAlarm(side: .right))
        #expect(pod.cleared == [.right])
        #expect(stopped.snapshot?.alarmSide == nil)

        let snoozed = await relay(pod).handle(.snoozeAlarm(side: .right, minutes: 5))
        #expect(pod.snoozed.map(\.1) == [300])
        #expect(snoozed.message?.hasPrefix("Snoozed until") == true)
    }

    @Test func aRefusedCommandFailsAndAnUnreadableStatusDoesToo() async throws {
        let pod = try await pod()
        pod.failUpdate = true
        let refused = await relay(pod).handle(.setPower(sides: [.left], on: true))
        #expect(refused.failed)
        #expect(refused.snapshot == nil)

        pod.status = nil
        let unreachable = await relay(pod).handle(.status)
        #expect(unreachable.failed)
        #expect(unreachable.message == "Couldn't reach the pod.")
    }

    @Test func noPodYetAsksForSetup() async {
        let reply = await WatchBedRelay().handle(.status)
        #expect(reply.failed)
        #expect(reply.message == "Set up your pod on iPhone first.")
    }

    @Test func sendingTheNightAnswersWithTheSummaryEvenIfStatusFails() async throws {
        let pod = RecordingPod()
        let relay = relay(pod)
        relay.sendNight = { "Sent 1 movement night" }
        let reply = await relay.handle(.sendNightToPod)
        #expect(reply.failed == false)
        #expect(reply.message == "Sent 1 movement night")
    }

    private func stored(_ status: WatchMotionUploadResult.Status) -> WatchMotionPodUpload.Outcome {
        .stored(WatchMotionUploadResult(id: 1, side: .left, version: "watch-motion-v2", recordedFromMs: 0, recordedToMs: 0,
                                        bins: 10, trimmedBins: 0, status: status))
    }

    @Test func nightSummarySaysWhatWasNewAndWhatWasLeftOut() {
        var health = PodWatchUpload.Report()
        health.heartRate = 1200
        health.hrv = 40
        #expect(WatchBedRelay.nightSummary(motion: [stored(.created)], health: health, healthProblem: nil)
            == "Sent 1 movement night and 1,240 Health readings")
        #expect(WatchBedRelay.nightSummary(motion: [stored(.unchanged)], health: PodWatchUpload.Report(), healthProblem: nil)
            == "Already on the pod")
        #expect(WatchBedRelay.nightSummary(motion: [.unsupported], health: nil, healthProblem: "Turn on Apple Health")
            == "Update the pod to store movement. Turn on Apple Health")
        #expect(WatchBedRelay.nightSummary(motion: [stored(.created), stored(.created), .failed("x")], health: nil, healthProblem: nil)
            == "Sent 2 movement nights. Some movement wasn't sent")
    }

    @Test func messagesSurviveTheTripBetweenWatchAndIPhone() throws {
        let request = WatchBed.Request.setTemperature(sides: [.left, .right], fahrenheit: 68)
        #expect(try WatchBed.decode(WatchBed.Request.self, from: WatchBed.message(request)) == request)
        let reply = WatchBed.Reply(snapshot: nil, message: "ok", failed: true)
        #expect(try WatchBed.decode(WatchBed.Reply.self, from: WatchBed.message(reply)) == reply)
        #expect(throws: (any Error).self) { try WatchBed.decode(WatchBed.Reply.self, from: [:]) }
    }

    @Test func valueTextFollowsTheIPhonesUnit() {
        #expect(WatchBed.valueText(68, unit: .fahrenheit) == "68°")
        #expect(WatchBed.valueText(68, unit: .celsius) == "20°")
        #expect(WatchBed.valueText(83, unit: .relative) == "+3")
        #expect(WatchBed.valueText(77, unit: .relative) == "−3")
        #expect(WatchBed.valueText(80, unit: .relative) == "0")
    }
}
