import SwiftUI

@main
struct SleepypodWatchApp: App {
    @State private var controller = Self.makeController()

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

    var body: some Scene {
        WindowGroup {
            RecorderView().environment(controller)
        }
    }
}

/// One job per screen: set the length and record, watch it run, or send it in the morning.
struct RecorderView: View {
    @Environment(RecordingController.self) private var controller
    @State private var showingInfo = false

    var body: some View {
        NavigationStack {
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
            .navigationTitle("sleepypod")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("About recording", systemImage: "info") { showingInfo = true }
                }
            }
            .sheet(isPresented: $showingInfo) { InfoView() }
        }
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
    let plan: RecordingPlan

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(.indigo)
            Text("\((plan.duration / 3600).formatted(.number.precision(.fractionLength(0...1)))) h recorded")
                .font(.headline)
            Spacer(minLength: 0)
            Button {
                Task { await controller.send() }
            } label: {
                Label(controller.busy ? "Sending…" : "Send to iPhone", systemImage: "iphone").frame(maxWidth: .infinity)
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

/// What the recorder is for, and the one advanced option, kept off the main screens.
private struct InfoView: View {
    @Environment(RecordingController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Records wrist movement overnight as labels for the pod's movement classifier.")
                    .font(.footnote)
                Text("It stays on this Watch until you send it to your iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Include raw 50 Hz", isOn: $controller.includeRaw).font(.footnote)
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
#endif
