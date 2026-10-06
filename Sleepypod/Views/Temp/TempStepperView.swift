import SwiftUI

enum StepperTab: Hashable {
    case now
    case phase(NightPhaseKey)

    var title: String {
        switch self {
        case .now: "Now"
        case .phase(let key): key.title
        }
    }
}

/// The Now / Night / Dawn stepper from sleepypod-core. Now drives the pod directly; Night and Dawn
/// edit tonight's schedule through `NightPhasesStore`.
struct TempStepperView: View {
    @Environment(DeviceManager.self) private var device
    @Environment(SettingsManager.self) private var settings
    let store: NightPhasesStore
    @Binding var tab: StepperTab

    private var side: Side { device.selectedSide.primarySide }
    private var sides: [Side] { device.isLinked ? [.left, .right] : [side] }
    private var phases: NightPhases? { store.phases[side] }
    private var target: Int { device.currentSideStatus?.targetTemperatureF ?? 80 }
    private var bed: Int { device.currentSideStatus?.currentTemperatureF ?? 80 }
    private var format: TemperatureFormat { settings.temperatureFormat }
    private var off: Bool { !device.isOn }
    private var tabs: [StepperTab] { [.now, .phase(.night), .phase(.dawn)] }

    /// The tab actually shown — Night / Dawn fall back to Now until phases load.
    private var selected: StepperTab {
        if case .phase(let key) = tab, phases?.phase(key) == nil { return .now }
        return tab
    }

    private func value(_ tab: StepperTab) -> Int? {
        switch tab {
        case .now: target
        case .phase(let key): store.value(side, key)
        }
    }

    private func available(_ tab: StepperTab) -> Bool {
        if case .phase(let key) = tab { return phases?.phase(key) != nil }
        return true
    }

    private func color(_ tab: StepperTab, _ value: Int) -> Color {
        switch tab {
        case .now: TempColor.forDelta(target: value, current: bed)
        case .phase: TempColor.forScheduled(value)
        }
    }

    /// Now gets a little more room; Night and Dawn split the rest by their length.
    private func grow(_ tab: StepperTab) -> CGFloat {
        let night = phases?.night.minutes ?? 1, dawn = phases?.dawn?.minutes ?? 0
        switch tab {
        case .now: return 1.2
        case .phase(.night): return max(1, 3 * night / (night + dawn))
        case .phase(.dawn): return dawn > 0 ? max(1, 3 * dawn / (night + dawn)) : 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Spacer(minLength: 12)
            HStack(spacing: 16) {
                stepButton(-1)
                Text(off ? "Off" : value(selected).map { TemperatureConversion.valueText($0, format: format) } ?? "—")
                    .font(.mono(52, weight: .light, relativeTo: .largeTitle))
                    .foregroundStyle(off ? Theme.text2 : Theme.text1)
                    .contentTransition(.numericText(value: Double(value(selected) ?? 0)))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(minWidth: 118)
                    .accessibilityLabel("\(selected.title) temperature")
                    .accessibilityValue(off ? "Off" : value(selected).map { TemperatureConversion.valueText($0, format: format) } ?? "unavailable")
                    .accessibilityAdjustableAction { direction in step(direction == .increment ? 1 : -1) }
                stepButton(1)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            Spacer(minLength: 12)
            caption
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(height: 250)
        .cardSurface()
        .animation(.snappy(duration: 0.2), value: value(selected))
    }

    private var tabBar: some View {
        GeometryReader { geo in
            let total = tabs.map(grow).reduce(0, +)
            let width = geo.size.width - 16
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { item in
                    let isSelected = item == selected
                    let ok = available(item) && !off
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy(duration: 0.2)) { tab = item }
                    } label: {
                        VStack(spacing: 6) {
                            if let v = value(item), available(item) {
                                Text(TemperatureConversion.valueText(v, format: format))
                                    .foregroundStyle(color(item, v))
                                    .opacity(phases?.draft == true && item != .now ? 0.6 : 1)
                            } else {
                                Text("—").foregroundStyle(Theme.text3)
                            }
                            Capsule().fill(isSelected ? Theme.text1 : Theme.border2).frame(height: 3)
                            Text(item.title).font(.footnote).foregroundStyle(isSelected ? Theme.text1 : Theme.text2)
                        }
                        .font(.mono(15, relativeTo: .subheadline))
                        .frame(width: max(40, width * grow(item) / total))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!ok)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(value(item).map { TemperatureConversion.valueText($0, format: format) } ?? "")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(height: 54)
        .opacity(off ? 0.35 : 1)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder private var caption: some View {
        VStack(spacing: 3) {
            if case .phase(let key) = selected, let phase = phases?.phase(key), !off {
                if let error = store.error {
                    Text(error).foregroundStyle(Theme.amber)
                } else {
                    Text("\(DisplayTime.clock(phase.start)) → \(DisplayTime.clock(phase.end))").foregroundStyle(Theme.text2)
                }
                if phases?.draft == true {
                    Text("Suggested · − / + saves it").foregroundStyle(Theme.text2)
                } else if let phases, store.error == nil {
                    Text(phases.daysSummary).foregroundStyle(Theme.text3)
                }
            } else {
                let state = TemperatureConversion.stateWord(target: target, bed: bed, isOn: !off)
                let bedText = TemperatureConversion.displayTemp(bed, format: format == .relative ? .fahrenheit : format)
                let stateText = Text(state).foregroundStyle(off ? Theme.text3 : TempColor.forDelta(target: target, current: bed))
                Text("\(stateText) · bed \(bedText)").foregroundStyle(Theme.text2)
                if !off && phases?.draft == true {
                    Button("Set up Night & Dawn") { withAnimation(.snappy(duration: 0.2)) { tab = .phase(.night) } }
                        .foregroundStyle(Theme.text1)
                } else if store.unsupported && !off {
                    Text(store.error ?? "").foregroundStyle(Theme.text3)
                }
            }
        }
        .font(.mono(13, relativeTo: .footnote))
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(minHeight: 36, alignment: .top)
        .buttonStyle(.plain)
    }

    private func stepButton(_ delta: Int) -> some View {
        let disabled = off || value(selected) == nil
        return Button { step(delta) } label: {
            Image(systemName: delta < 0 ? "minus" : "plus").font(.system(size: 22))
                .foregroundStyle(Theme.text1)
                .frame(width: 56, height: 56)
                .background(Theme.active, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(off ? 0.35 : disabled ? 0.4 : 1)
        .accessibilityLabel("\(delta < 0 ? "Cooler" : "Warmer") \(selected.title.lowercased())")
    }

    private func step(_ delta: Int) {
        guard !off else { return }
        Haptics.light()
        switch selected {
        case .now: device.setTemperature(NightPhasesStore.step(target, delta: delta, format: format))
        case .phase(let key): store.nudge(sides, phase: key, delta: delta, format: format)
        }
    }
}
