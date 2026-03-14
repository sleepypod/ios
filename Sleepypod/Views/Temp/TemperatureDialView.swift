import SwiftUI

struct TemperatureDialView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager

    private let dialSize: CGFloat = 280
    private let ringWidth: CGFloat = 6
    private let thumbSize: CGFloat = 22

    // Dial arc: 3/4 circle (from 135° to 405°, i.e. 270° sweep)
    private let startAngle: Double = 135
    private let endAngle: Double = 405
    private let totalSweep: Double = 270

    @State private var isDragging = false

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
        return TempColor.forOffset(targetOffset)
    }

    private var tempColor: Color {
        guard isOn else { return Theme.textMuted }
        return TempColor.forOffset(targetOffset)
    }

    private var glowColor: Color {
        guard isOn else { return Color.gray.opacity(0.2) }
        return TempColor.glowForOffset(targetOffset)
    }

    private var directionLabel: String? {
        guard isOn else { return nil }
        if targetOffset > 0 { return "WARMING TO" }
        if targetOffset < 0 { return "COOLING TO" }
        return nil
    }

    /// Normalized progress 0...1 for the target temp within the dial range
    private var targetProgress: Double {
        let clamped = max(TemperatureConversion.minOffset, min(TemperatureConversion.maxOffset, targetOffset))
        return Double(clamped - TemperatureConversion.minOffset) / Double(TemperatureConversion.maxOffset - TemperatureConversion.minOffset)
    }

    /// Normalized progress for current temp (for the filled arc)
    private var currentProgress: Double {
        let clamped = max(TemperatureConversion.minOffset, min(TemperatureConversion.maxOffset, currentOffset))
        return Double(clamped - TemperatureConversion.minOffset) / Double(TemperatureConversion.maxOffset - TemperatureConversion.minOffset)
    }

    var body: some View {
        ZStack {
            // Background track (full arc)
            arcShape(progress: 1.0)
                .stroke(Color(hex: "222222"), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: dialSize, height: dialSize)

            // Filled arc to target position
            if isOn {
                arcShape(progress: targetProgress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .frame(width: dialSize, height: dialSize)
                    .shadow(color: glowColor, radius: 20)
                    .shadow(color: glowColor, radius: 10)
            }

            // Draggable thumb
            if isOn {
                thumbView
            }

            // Center content
            VStack(spacing: 4) {
                if isOn {
                    if let label = directionLabel {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(tempColor.opacity(0.8))
                            .padding(.bottom, 2)
                    }

                    Text(absoluteTempDisplay)
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .foregroundColor(tempColor)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: targetTempF)

                    Text("Currently at \(currentTempDisplay)")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .padding(.top, 2)

                    if let remaining = sideStatus?.secondsRemaining, remaining > 0 {
                        Text(formatRemaining(remaining))
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
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

        // Map progress to offset
        let newOffset = TemperatureConversion.minOffset + Int(round(progress * Double(TemperatureConversion.maxOffset - TemperatureConversion.minOffset)))
        let clampedOffset = max(TemperatureConversion.minOffset, min(TemperatureConversion.maxOffset, newOffset))

        if clampedOffset != targetOffset {
            Haptics.light()
            let newTempF = TemperatureConversion.offsetToTempF(clampedOffset)
            deviceManager.setTemperature(newTempF)
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
        if hours > 0 { return "Turns off in \(hours)h \(minutes)m" }
        return "Turns off in \(minutes)m"
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
