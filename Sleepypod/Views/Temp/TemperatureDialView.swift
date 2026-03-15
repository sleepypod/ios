import SwiftUI

struct TemperatureDialView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    private let dialSize: CGFloat = 280
    private let ringWidth: CGFloat = 10
    private let thumbSize: CGFloat = 22

    // Dial arc: 3/4 circle (from 135° to 405°, i.e. 270° sweep)
    private let startAngle: Double = 135
    private let endAngle: Double = 405
    private let totalSweep: Double = 270

    @State private var isDragging = false
    @State private var glowPulse = false

    private var sideStatus: SideStatus? {
        deviceManager.currentSideStatus
    }

    private var isOn: Bool {
        sideStatus?.isOn ?? false
    }

    private var targetTempF: Int {
        sideStatus?.targetTemperatureF ?? 80
    }

    private var currentTempF: Int {
        sideStatus?.currentTemperatureF ?? 80
    }

    private var targetOffset: Int {
        TemperatureConversion.tempFToOffset(targetTempF)
    }

    private var currentOffset: Int {
        TemperatureConversion.tempFToOffset(currentTempF)
    }

    private var ringColor: Color {
        guard isOn else { return Color(hex: "333333") }
        return TempColor.forDelta(target: targetTempF, current: currentTempF)
    }

    private var tempColor: Color {
        guard isOn else { return Theme.textMuted }
        return TempColor.forDelta(target: targetTempF, current: currentTempF)
    }

    private var glowColor: Color {
        guard isOn else { return Color.gray.opacity(0.2) }
        return TempColor.glowForDelta(target: targetTempF, current: currentTempF)
    }

    private var directionLabel: (text: String, icon: String, color: Color)? {
        guard isOn else { return nil }
        if targetTempF > currentTempF { return ("WARMING", "flame.fill", Theme.warming) }
        if targetTempF < currentTempF { return ("COOLING", "snowflake", Theme.cooling) }
        return nil
    }

    /// Normalized progress 0...1 for the target temp within the dial range
    private var targetProgress: Double {
        let clamped = max(TemperatureConversion.minTempF, min(TemperatureConversion.maxTempF, targetTempF))
        return Double(clamped - TemperatureConversion.minTempF) / Double(TemperatureConversion.maxTempF - TemperatureConversion.minTempF)
    }

    /// Normalized progress for current temp (for the filled arc)
    private var currentProgress: Double {
        let clamped = max(TemperatureConversion.minTempF, min(TemperatureConversion.maxTempF, currentTempF))
        return Double(clamped - TemperatureConversion.minTempF) / Double(TemperatureConversion.maxTempF - TemperatureConversion.minTempF)
    }

    var body: some View {
        ZStack {
            // Background track (full arc)
            arcShape(progress: 1.0)
                .stroke(Color(hex: "222222"), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: dialSize, height: dialSize)

            // Colored arc between current and target (the "journey")
            if isOn && targetTempF != currentTempF {
                let fromProgress = min(currentProgress, targetProgress)
                let toProgress = max(currentProgress, targetProgress)
                Arc(startAngle: .degrees(startAngle + fromProgress * totalSweep),
                    endAngle: .degrees(startAngle + toProgress * totalSweep))
                    .stroke(ringColor.opacity(0.4), style: StrokeStyle(lineWidth: ringWidth + 4, lineCap: .round))
                    .frame(width: dialSize, height: dialSize)
                    .shadow(color: glowColor, radius: glowPulse ? 50 : 30)
                    .shadow(color: glowColor, radius: glowPulse ? 25 : 15)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowPulse)
                    .onAppear { glowPulse = true }
            }

            // Target position marker on ring
            if isOn {
                arcShape(progress: targetProgress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .frame(width: dialSize, height: dialSize)
                    .shadow(color: glowColor, radius: 8)
            }

            // Current temp marker (where you are)
            if isOn {
                currentTempMarker
            }

            // Draggable thumb (where you're going)
            if isOn {
                thumbView
            }

            // Center content
            VStack(spacing: 4) {
                if isOn {
                    if let direction = directionLabel {
                        HStack(spacing: 6) {
                            Image(systemName: direction.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(direction.color)
                                .symbolEffect(.pulse)
                            Text(direction.text)
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(2)
                                .foregroundColor(direction.color.opacity(0.9))
                        }
                        .padding(.bottom, 2)
                    }

                    if settingsManager.temperatureFormat == .relative {
                        // Relative mode: offset is the hero
                        Text(TemperatureConversion.offsetDisplay(targetOffset))
                            .font(.system(size: 56, weight: .light, design: .rounded))
                            .foregroundColor(tempColor)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: targetOffset)

                        Text("Now \(TemperatureConversion.displayTemp(currentTempF, format: .fahrenheit))")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                            .padding(.top, 2)
                    } else {
                        // Absolute mode: temp is the hero, offset below
                        Text(absoluteTempDisplay)
                            .font(.system(size: 56, weight: .light, design: .rounded))
                            .foregroundColor(tempColor)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: targetTempF)

                        HStack(spacing: 12) {
                            Text(TemperatureConversion.offsetDisplay(targetOffset))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(tempColor.opacity(0.7))
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.2), value: targetOffset)

                            Text("·")
                                .foregroundColor(Theme.textMuted)

                            Text("Now \(currentTempDisplay)")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textMuted)
                        }
                        .padding(.top, 2)
                    }

                } else {
                    Text("OFF")
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Current Temp Marker

    private var currentTempMarker: some View {
        let angle = startAngle + currentProgress * totalSweep
        let radius = dialSize / 2
        let radians = angle * .pi / 180
        let tickX = cos(radians) * radius
        let tickY = sin(radians) * radius
        let labelX = cos(radians) * (radius + 16)
        let labelY = sin(radians) * (radius + 16)

        return Group {
            Capsule()
                .fill(.white.opacity(0.6))
                .frame(width: 2, height: 12)
                .rotationEffect(.degrees(angle + 90))
                .offset(x: tickX, y: tickY)

            Text("NOW")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .offset(x: labelX, y: labelY)
        }
    }

    // MARK: - Thumb

    private var thumbView: some View {
        let angle = startAngle + targetProgress * totalSweep
        let radius = dialSize / 2
        let radians = angle * .pi / 180
        let x = cos(radians) * radius
        let y = sin(radians) * radius

        return Circle()
            .fill(.white)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: glowColor, radius: 12)
            .shadow(color: glowColor, radius: 6)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .offset(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            Haptics.light()
                        }
                        handleDrag(value.location, in: dialSize)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }

    // MARK: - Arc Shape

    private func arcShape(progress: Double) -> some Shape {
        Arc(startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + progress * totalSweep))
    }

    // MARK: - Drag Handling

    private func handleDrag(_ location: CGPoint, in size: CGFloat) {
        // location is relative to the thumb's container (the ZStack)
        // Center of the dial is at (0, 0) since thumb is offset from center
        let center = CGPoint(x: 0, y: 0)
        let dx = location.x - center.x
        let dy = location.y - center.y

        // Calculate angle from center
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }

        // Map angle to progress (startAngle=135 to endAngle=405)
        var normalizedAngle = angle
        if normalizedAngle < startAngle { normalizedAngle += 360 }
        let progress = (normalizedAngle - startAngle) / totalSweep

        guard progress >= 0, progress <= 1 else { return }

        // Map progress to temperature
        let range = TemperatureConversion.maxTempF - TemperatureConversion.minTempF
        let newTempF = TemperatureConversion.minTempF + Int(round(progress * Double(range)))
        let clamped = max(TemperatureConversion.minTempF, min(TemperatureConversion.maxTempF, newTempF))

        if clamped != targetTempF {
            Haptics.light()
            deviceManager.setTemperature(clamped)
        }
    }

    // MARK: - Display Helpers

    private var absoluteTempDisplay: String {
        TemperatureConversion.displayTemp(targetTempF, format: settingsManager.temperatureFormat)
    }

    private var currentTempDisplay: String {
        TemperatureConversion.displayTemp(currentTempF, format: settingsManager.temperatureFormat)
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "Auto-off in \(hours)h \(minutes)m" }
        return "Auto-off in \(minutes)m"
    }
}

// MARK: - Arc Shape

private struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center, radius: radius,
                    startAngle: startAngle, endAngle: endAngle,
                    clockwise: false)
        return path
    }
}
