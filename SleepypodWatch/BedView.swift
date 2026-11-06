import SwiftUI

/// The bed on one screen: the target on the Crown, the bed's own temperature under it, and power below.
struct BedView: View {
    @Environment(BedController.self) private var bed
    @Environment(RecordingController.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase
    @State private var choosingSide = false
    /// The Crown sets the target here, so the recorder below needs a button as well as a swipe.
    var showMovement: () -> Void = {}

    var body: some View {
        @Bindable var bed = bed
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            if bed.snapshot == nil {
                ProgressView().opacity(bed.busy ? 1 : 0)
                Text("Open sleepypod on iPhone once to connect.").font(.footnote).multilineTextAlignment(.center)
                    .opacity(bed.busy ? 0 : 1)
            } else {
                Text(WatchBed.valueText(Int(bed.draftF.rounded()), unit: bed.unit))
                    .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(bed.isOn ? .primary : .secondary)
                    .contentTransition(.numericText(value: bed.draftF))
                    .focusable(bed.isOn)
                    .digitalCrownRotation($bed.draftF, from: Double(WatchBed.minF), through: Double(WatchBed.maxF), by: 1,
                                          sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .onChange(of: bed.draftF) { bed.draftChanged() }
                    .accessibilityLabel("Target \(WatchBed.valueText(Int(bed.draftF.rounded()), unit: bed.unit))")
                    .accessibilityHint(bed.isOn ? "Turn the Digital Crown to change" : "Turn the bed on to change")
                BedReading(state: bed.shown, isOn: bed.isOn, unit: bed.unit)
            }
            Spacer(minLength: 0)
            Button {
                Task { await bed.togglePower() }
            } label: {
                Label(bed.isOn ? "Turn off" : "Turn on", systemImage: "power").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(bed.isOn ? .gray : .blue)
            .disabled(bed.snapshot == nil || bed.busy)
            if let note = bed.notice {
                Text(note).font(.caption2).foregroundStyle(bed.failed || bed.status.isEmpty ? .orange : .secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .navigationTitle(bed.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Side", systemImage: bed.selection == .both ? "person.2" : "person") { choosingSide = true }
                    .disabled(bed.snapshot == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                let recording = if case .recording = recorder.phase() { true } else { false }
                Button("Movement", systemImage: recording ? "record.circle.fill" : "waveform.path", action: showMovement)
                    .foregroundStyle(recording ? .red : .primary)
                    .accessibilityValue(recording ? "Recording" : "")
            }
        }
        .sheet(isPresented: $choosingSide) { SidePicker() }
        .task(id: scenePhase) {
            // Stays current while the screen is up; the iPhone answers each check from its connection.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                if !bed.editing { await bed.refresh() }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}

/// "Bed 75° · cooling", so a change shows it is working.
private struct BedReading: View {
    let state: WatchBed.SideState?
    let isOn: Bool
    let unit: WatchBed.Unit

    var body: some View {
        if !isOn {
            Text("Off").font(.footnote).foregroundStyle(.secondary)
        } else if let current = state?.currentF, let target = state?.targetF {
            let word = target < current ? "cooling" : target > current ? "warming" : "holding"
            let tint: Color = target < current ? .cyan : target > current ? .orange : .secondary
            Label("Bed \(WatchBed.valueText(current, unit: unit)) · \(word)",
                  systemImage: target < current ? "snowflake" : target > current ? "flame" : "equal")
                .font(.footnote).foregroundStyle(tint)
        }
    }
}

private struct SidePicker: View {
    @Environment(BedController.self) private var bed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(BedController.Selection.allCases, id: \.self) { selection in
                Button {
                    bed.selection = selection
                    dismiss()
                } label: {
                    HStack {
                        Text(name(selection))
                        Spacer()
                        if bed.selection == selection { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .navigationTitle("Side")
    }

    private func name(_ selection: BedController.Selection) -> String {
        switch selection {
        case .left: bed.snapshot?.state(.left)?.name ?? "Left"
        case .right: bed.snapshot?.state(.right)?.name ?? "Right"
        case .both: "Both sides"
        }
    }
}

/// Takes over while an alarm vibrates, so stopping it is one tap from a dark room.
struct AlarmView: View {
    @Environment(BedController.self) private var bed

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "alarm.waves.left.and.right.fill").font(.title2).foregroundStyle(.orange)
                .symbolEffect(.wiggle, options: .repeat(.continuous))
            Text("Alarm").font(.headline)
            Spacer(minLength: 0)
            Button {
                Task { await bed.stopAlarm() }
            } label: {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.orange)
            Button {
                Task { await bed.snoozeAlarm() }
            } label: {
                Label("Snooze 5 min", systemImage: "zzz").frame(maxWidth: .infinity)
            }
        }
        .disabled(bed.busy)
        .task {
            // Checks more often here so a stop from the iPhone or the bed clears this screen quickly.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await bed.refresh()
            }
        }
    }
}
