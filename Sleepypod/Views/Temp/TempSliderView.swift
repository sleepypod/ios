import SwiftUI

/// 1c: a tall thumb-drag pill like Control Center, easy to use half-asleep.
struct TempSliderView: View {
    @Environment(DeviceManager.self) private var device
    @Environment(SettingsManager.self) private var settings
    let curve: ActiveCurve?
    let profileName: String

    private var target: Int { device.currentSideStatus?.targetTemperatureF ?? 80 }
    private var bed: Int { device.currentSideStatus?.currentTemperatureF ?? 80 }
    private var format: TemperatureFormat { settings.temperatureFormat }
    private var color: Color { device.isOn ? TempColor.forDelta(target: target, current: bed) : Theme.text3 }
    private static func fraction(_ tempF: Int) -> CGFloat { CGFloat(min(110, max(55, tempF)) - 55) / 55 }

    var body: some View {
        GeometryReader { geo in
            let pillHeight = min(500, max(260, geo.size.height - 64 - 28))
            VStack(spacing: 28) {
                HStack(alignment: .top, spacing: 0) {
                    pill(height: pillHeight).padding(.leading, 12)
                    scaleLabels(height: pillHeight).padding(.leading, 8)
                    readout
                        .padding(.top, pillHeight * 0.32)
                        .padding(.leading, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: pillHeight)
                tiles
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func pill(height: CGFloat) -> some View {
        let fill = Self.fraction(target) * height
        return ZStack(alignment: .bottom) {
            Theme.track
            Rectangle().fill(color.opacity(device.isOn ? 1 : 0.35)).frame(height: fill)
            Rectangle().fill(.clear).frame(height: 1)
                .overlay(Line().stroke(Theme.text3, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .offset(y: -Self.fraction(bed) * height)
            Capsule().fill(Theme.text1.opacity(0.9)).frame(height: 5).padding(.horizontal, 44)
                .offset(y: -min(height - 24, fill + 14))
        }
        .frame(width: 128, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            guard device.isOn else { return }
            let fraction = 1 - min(1, max(0, drag.location.y / height))
            let value = 55 + Int((fraction * 55).rounded())
            if value != target { Haptics.light(); device.setTemperature(value) }
        })
        .animation(.snappy(duration: 0.15), value: target)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target temperature")
        .accessibilityValue("\(TemperatureConversion.valueText(target, format: format)), \(TemperatureConversion.stateWord(target: target, bed: bed, isOn: device.isOn).lowercased())")
        .accessibilityAdjustableAction { direction in
            guard device.isOn else { return }
            device.setTemperature(target + (direction == .increment ? 1 : -1))
        }
    }

    private func scaleLabels(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text(TemperatureConversion.valueText(110, format: format == .relative ? .fahrenheit : format))
            Text(TemperatureConversion.valueText(bed, format: format == .relative ? .fahrenheit : format))
                .offset(y: (1 - Self.fraction(bed)) * height - 7)
            Text(TemperatureConversion.valueText(55, format: format == .relative ? .fahrenheit : format))
                .offset(y: height - 14)
        }
        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text3)
        .frame(width: 34, height: height, alignment: .topLeading)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityHidden(true)
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TemperatureConversion.stateWord(target: target, bed: bed, isOn: device.isOn))
                .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(color)
            Text(TemperatureConversion.valueText(target, format: format))
                .font(.mono(84, weight: .light, relativeTo: .largeTitle)).tracking(-3)
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(target)))
            Text("\(TemperatureConversion.offsetDisplay(target - bed)) · bed \(TemperatureConversion.displayTemp(bed, format: format == .relative ? .fahrenheit : format))")
                .font(.mono(13, relativeTo: .footnote)).foregroundStyle(Theme.text2)
            if let status = device.currentSideStatus, status.isOn, status.secondsRemaining > 0 {
                Label("off in \(DisplayTime.duration(status.secondsRemaining))", systemImage: "timer")
                    .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
                    .labelStyle(TightLabelStyle())
                    .padding(.top, 8)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.snappy(duration: 0.15), value: target)
        .accessibilityHidden(true)
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.medium()
                device.togglePower()
            } label: {
                Label(device.isOn ? "On" : "Off", systemImage: "power")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(device.isOn ? Theme.background : Theme.text1)
                    .background(device.isOn ? Theme.text1 : Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        if !device.isOn { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border1, lineWidth: 1) }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(device.isOn ? "Turn off" : "Turn on")
            VStack(alignment: .leading, spacing: 3) {
                Text(curve == nil ? "No schedule" : profileName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(curve.map { "\(DisplayTime.clock($0.bedtime)) →" } ?? "Set one up in Schedule")
                    .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .cardSurface()
            .accessibilityElement(children: .combine)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon; configuration.title }
    }
}
