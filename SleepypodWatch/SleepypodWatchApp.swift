import SwiftUI

@main
struct SleepypodWatchApp: App {
    @State private var controller = Self.makeController()
    @State private var bed = Self.makeBed()

    private static func makeController() -> RecordingController {
        #if DEBUG
        // `-previewPhase ready|recording|finished` shows a screen in the simulator, which has no accelerometer.
        if let phase = UserDefaults.standard.string(forKey: "previewPhase") {
            let defaults = UserDefaults(suiteName: "watch-preview")!
            defaults.removePersistentDomain(forName: "watch-preview")
            let controller = RecordingController(source: PreviewAccelerometer(), defaults: defaults)
            switch phase {
            case "recording": controller.recordTonight(now: .now.addingTimeInterval(-2 * 3600))
            case "finished": controller.recordTonight(now: .now.addingTimeInterval(-10 * 3600))
            default: break
            }
            return controller
        }
        #endif
        return RecordingController()
    }

    private static func makeBed() -> BedController {
        #if DEBUG
        // `-previewBed on|off|alarm` shows the bed without a paired iPhone.
        if let mode = UserDefaults.standard.string(forKey: "previewBed") {
            let defaults = UserDefaults(suiteName: "watch-preview-bed")!
            defaults.removePersistentDomain(forName: "watch-preview-bed")
            return BedController(link: PreviewPhone(mode: mode), defaults: defaults)
        }
        #endif
        return BedController()
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(controller).environment(bed)
        }
    }
}

/// The bed first, the movement recorder a swipe down; an alarm takes over both.
struct RootView: View {
    @Environment(RecordingController.self) private var controller
    @Environment(BedController.self) private var bed
    @State private var page = Page.bed

    enum Page { case bed, recorder }

    var body: some View {
        NavigationStack {
            if bed.snapshot?.alarmSide != nil {
                AlarmView()
            } else {
                TabView(selection: $page) {
                    BedView().tag(Page.bed)
                    RecorderView().tag(Page.recorder)
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .onAppear {
            // A finished night waiting to be sent is the morning's one job.
            if case .finished = controller.phase() { page = .recorder }
        }
    }
}

/// One job per screen: set the length and record, watch it run, or send it in the morning.
struct RecorderView: View {
    @Environment(RecordingController.self) private var controller
    @State private var showingInfo = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if !controller.canRecord {
                    UnavailableView(message: controller.availability)
                } else {
                    switch controller.phase(now: context.date) {
                    case .ready: ReadyView(now: context.date)
                    case .recording(let plan): RecordingView(plan: plan)
                    case .finished(let plan): FinishedView(plan: plan)
                    }
                }
            }
        }
        .navigationTitle("Movement")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("About recording", systemImage: "info") { showingInfo = true }
            }
        }
        .sheet(isPresented: $showingInfo) { InfoView() }
    }
}

private struct ReadyView: View {
    @Environment(RecordingController.self) private var controller
    let now: Date

    var body: some View {
        @Bindable var controller = controller
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text("\(controller.hours.formatted(.number.precision(.fractionLength(0...1)))) h")
                .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText(value: controller.hours))
                .focusable()
                .digitalCrownRotation($controller.hours, from: 1, through: 12, by: 0.5, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel("Record for \(controller.hours.formatted()) hours")
                .accessibilityHint("Turn the Digital Crown to change")
            Text("until \(now.addingTimeInterval(controller.hours * 3600).formatted(date: .omitted, time: .shortened))")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                controller.recordTonight()
            } label: {
                Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red)
            if !controller.status.isEmpty {
                Text(controller.status).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecordingView: View {
    @Environment(RecordingController.self) private var controller
    @State private var confirmingStop = false
    let plan: RecordingPlan

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Label("Recording", systemImage: "circle.fill").font(.footnote).foregroundStyle(.red)
                .symbolEffect(.pulse)
            Text(timerInterval: plan.start...plan.end, countsDown: true)
                .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("until \(plan.end.formatted(date: .omitted, time: .shortened))")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                confirmingStop = true
            } label: {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            Text("You can close the app.").font(.caption2).foregroundStyle(.secondary)
        }
        .confirmationDialog("Stop recording?", isPresented: $confirmingStop) {
            Button("Stop", role: .destructive) { controller.stop() }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("What's recorded so far is kept to send.")
        }
    }
}

private struct FinishedView: View {
    @Environment(RecordingController.self) private var controller
    @Environment(BedController.self) private var bed
    let plan: RecordingPlan

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(.indigo)
            Text("\((plan.duration / 3600).formatted(.number.precision(.fractionLength(0...1)))) h recorded")
                .font(.headline)
            Spacer(minLength: 0)
            Button {
                Task {
                    await controller.send()
                    // The iPhone sends the movement on as it arrives; this adds the night's Health readings.
                    guard controller.phase() == .ready else { return }
                    let line = await bed.sendNightToPod()
                    // Out of reach, the recording still waits in the queue, so "Sent to iPhone" stays.
                    if !bed.failed { controller.note(line) }
                }
            } label: {
                Label(controller.busy ? "Sending…" : "Send to pod", systemImage: "arrow.up.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.blue)
            .disabled(controller.busy)
            if !controller.status.isEmpty {
                Text(controller.status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}

private struct UnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk.motion.trianglebadge.exclamationmark").font(.title2).foregroundStyle(.orange)
            Text(message).font(.footnote).multilineTextAlignment(.center)
        }
    }
}

/// What the recorder is for, and the advanced options, kept off the main screens.
private struct InfoView: View {
    @Environment(RecordingController.self) private var controller
    @Environment(BedController.self) private var bed

    var body: some View {
        @Bindable var controller = controller
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Records wrist movement overnight as labels for the pod's movement classifier.")
                    .font(.footnote)
                Text("It stays on this Watch until you send it. Your iPhone passes it to your pod with the night's heart rate, HRV, breathing and sleep stages from Health.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Include raw 50 Hz", isOn: $controller.includeRaw).font(.footnote)
                Button {
                    Task { await bed.sendNightToPod() }
                } label: {
                    Label(bed.busy ? "Sending…" : "Resend last 2 nights", systemImage: "arrow.clockwise")
                }
                .disabled(bed.busy)
                if !bed.status.isEmpty {
                    Text(bed.status).font(.caption2).foregroundStyle(bed.failed ? .orange : .secondary)
                }
            }
        }
    }
}

#if DEBUG
private struct PreviewAccelerometer: AccelerometerSource {
    var isAvailable: Bool { true }
    var authorization: MotionAuthorization { .authorized }
    func record(duration: TimeInterval) {}
    func samples(in interval: DateInterval) -> [MotionSample] { [] }
}

private struct PreviewPhone: PhoneLink {
    let mode: String

    func send(_ request: WatchBed.Request) async throws -> WatchBed.Reply {
        let on = mode != "off"
        let sides = WatchBed.Side.allCases.map { side in
            WatchBed.SideState(side: side, name: side == .left ? "Me" : "Partner", isOn: on, currentF: 75, targetF: 68,
                               isAlarmVibrating: mode == "alarm" && side == .left)
        }
        return WatchBed.Reply(snapshot: WatchBed.Snapshot(sides: sides, defaultSide: .left, unit: .fahrenheit,
                                                          waterLow: false, isPriming: false, takenAt: .now))
    }
}
#endif
