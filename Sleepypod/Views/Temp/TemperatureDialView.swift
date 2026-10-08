import SwiftUI

struct TemperatureDialView: View {
    @Environment(DeviceManager.self) private var device
    @Environment(SettingsManager.self) private var settings
    private let size: CGFloat = 300
    /// The source draws r=120 in a 280 viewBox scaled to 300pt.
    private var radius: CGFloat { size * 120 / 280 }
    private var target: Int { device.currentSideStatus?.targetTemperatureF ?? 80 }
    private var bed: Int { device.currentSideStatus?.currentTemperatureF ?? 80 }
    private var color: Color { TempColor.forDelta(target: target, current: bed) }
    private var progress: Double { Double(max(55, min(110, target)) - 55) / 55 }
    private var state: String { !device.isOn ? "OFF" : target < bed ? "COOLING" : target > bed ? "WARMING" : "HOLDING" }
    private var value: String {
        if settings.temperatureFormat == .relative { return TemperatureConversion.offsetDisplay(target - 80) }
        return "\(settings.temperatureFormat == .celsius ? Int(TemperatureConversion.tempFToC(target).rounded()) : target)°"
    }
    private var bedFormat: TemperatureFormat {
        settings.temperatureFormat == .relative ? .fahrenheit : settings.temperatureFormat
    }

    var body: some View {
        ZStack {
            DialArc(radius: radius, progress: 1).stroke(Theme.track, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            DialArc(radius: radius, progress: progress)
                .stroke(device.isOn ? color : Theme.text3, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            let angle = (135 + progress * 270) * .pi / 180
            Circle().fill(Theme.text1).frame(width: 24, height: 24)
                .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            VStack(spacing: 8) {
                Text(value).font(.mono(76, weight: .light, relativeTo: .largeTitle)).tracking(-2)
                    .foregroundStyle(Theme.text1).minimumScaleFactor(0.5).lineLimit(1)
                    .contentTransition(.numericText(value: Double(target)))
                Text("\(TemperatureConversion.offsetDisplay(target - bed)) · bed \(TemperatureConversion.displayTemp(bed, format: bedFormat))")
                    .font(.mono(13, relativeTo: .footnote)).foregroundStyle(Theme.text2)
                Text(state).font(.caption.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(device.isOn ? color : Theme.text3)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.snappy(duration: 0.2), value: target)
        .gesture(DragGesture(minimumDistance: 4).onChanged { drag in
            guard device.isOn else { return }
            var angle = atan2(drag.location.y - size / 2, drag.location.x - size / 2) * 180 / .pi
            if angle < 90 { angle += 360 }
            let clamped = min(405, max(135, angle))
            let value = 55 + Int(((clamped - 135) / 270 * 55).rounded())
            if value != target { Haptics.light(); device.setTemperature(value) }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target temperature")
        .accessibilityValue("\(value), \(state.lowercased())")
        .accessibilityAdjustableAction { direction in
            guard device.isOn else { return }
            device.setTemperature(target + (direction == .increment ? 1 : -1))
        }
    }
}

private struct DialArc: Shape {
    let radius: CGFloat
    let progress: Double
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                        startAngle: .degrees(135), endAngle: .degrees(135 + max(0.001, progress) * 270), clockwise: false)
        }
    }
}
