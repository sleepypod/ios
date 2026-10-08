import SwiftUI

/// 1b: both sides at once, each a card with its own power, ± and a track marking bed temp.
struct BothSidesView: View {
    @Environment(DeviceManager.self) private var device
    @Environment(SettingsManager.self) private var settings
    @Environment(SensorStreamService.self) private var sensor
    let curve: ActiveCurve?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subtitle).font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
                .padding(.horizontal, 4).padding(.top, -4).padding(.bottom, 2)
            ForEach(Side.allCases) { side in SideTempCard(side: side) }
            if let next { nextCard(next) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var subtitle: String {
        var parts = [device.deviceStatus?.podModelName ?? "Pod"]
        if let ambient = sensor.leftTemps?.amb ?? sensor.rightTemps?.amb, ambient.isFinite, ambient > -100 {
            let format = settings.temperatureFormat == .relative ? .fahrenheit : settings.temperatureFormat
            parts.append("\(TemperatureConversion.displayTemp(Int((ambient * 9 / 5 + 32).rounded()), format: format)) inside")
        }
        if device.isLinked { parts.append("linked") }
        return parts.joined(separator: " · ")
    }

    /// The next schedule event: bedtime before the night starts, wake while it runs.
    private var next: (String, String)? {
        guard let curve else { return nil }
        let now = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        let start = DisplayTime.minutes(curve.bedtime), end = DisplayTime.minutes(curve.wakeTime)
        let inNight = start <= end ? (now >= start && now < end) : (now >= start || now < end)
        return inNight ? ("Wake and warm-up", curve.wakeTime) : ("Bedtime curve starts", curve.bedtime)
    }

    private func nextCard(_ next: (String, String)) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("NEXT")
                Text(next.0).font(.subheadline)
            }
            Spacer()
            Text(DisplayTime.clock(next.1)).font(.mono(15, relativeTo: .subheadline))
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

private struct SideTempCard: View {
    @Environment(DeviceManager.self) private var device
    @Environment(SettingsManager.self) private var settings
    @Environment(SensorStreamService.self) private var sensor
    let side: Side

    private var status: SideStatus? { device.deviceStatus?.status(for: side) }
    private var target: Int { status?.targetTemperatureF ?? 80 }
    private var bed: Int { status?.currentTemperatureF ?? 80 }
    private var isOn: Bool { status?.isOn ?? false }
    private var color: Color { isOn ? TempColor.forDelta(target: target, current: bed) : Theme.text3 }
    private static func fraction(_ tempF: Int) -> CGFloat { CGFloat(min(110, max(55, tempF)) - 55) / 55 }

    var body: some View {
        let occupied = sensor.isOccupied(side: side)
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Text(settings.sideName(for: side)).font(.headline).lineLimit(1)
                    HStack(spacing: 5) {
                        if occupied { StatusDot() }
                        Eyebrow("\(side.rawValue.uppercased()) · \(occupied ? "IN BED" : "AWAY")")
                    }
                }
                Spacer(minLength: 8)
                Toggle("Power", isOn: Binding(get: { isOn }, set: { _ in
                    Haptics.medium()
                    device.togglePower(side: side)
                }))
                .labelsHidden().tint(Theme.green)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TemperatureConversion.valueText(target, format: settings.temperatureFormat))
                        .font(.mono(60, weight: .light, relativeTo: .largeTitle)).tracking(-1.5)
                        .foregroundStyle(isOn ? Theme.text1 : Theme.text2)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: Double(target)))
                    HStack(spacing: 10) {
                        Text(TemperatureConversion.stateWord(target: target, bed: bed, isOn: isOn))
                            .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(color)
                        Text(TemperatureConversion.offsetDisplay(target - bed))
                            .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    step("minus", delta: -1)
                    step("plus", delta: 1)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track).frame(height: 6)
                    Capsule().fill(color).frame(width: max(6, geo.size.width * Self.fraction(target)), height: 6)
                    Rectangle().fill(Theme.text3).frame(width: 2, height: 14)
                        .offset(x: geo.size.width * Self.fraction(bed) - 1)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            .accessibilityHidden(true)
        }
        .cardStyle(vertical: 18, horizontal: 18)
        .animation(.snappy(duration: 0.2), value: target)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(settings.sideName(for: side))
    }

    private func step(_ symbol: String, delta: Int) -> some View {
        Button {
            Haptics.light()
            device.setTemperature(target + delta, side: side)
        } label: {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Theme.text1)
                .frame(width: 52, height: 52)
                .background(Theme.active, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn || (delta < 0 ? target <= 55 : target >= 110))
        .opacity(isOn ? 1 : 0.45)
        .accessibilityLabel("\(delta < 0 ? "Cooler" : "Warmer"), \(settings.sideName(for: side))")
    }
}
