import SwiftUI
import Charts

struct BedSensorScreen: View {
    @Environment(SensorStreamService.self) private var sensor
    @Environment(SettingsManager.self) private var settingsManager

    @State private var livePulse = false
    @State private var fanRotation: Double = 0
    @State private var showGestureBadge = false
    @State private var gestureSide: String = ""
    @State private var gestureTapType: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                connectionBar

                // Gesture tap indicator
                if showGestureBadge {
                    HStack {
                        if gestureSide == "left" || gestureSide == "both" {
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 12))
                            Text("TAP")
                                .font(.caption.weight(.bold))
                            Text(gestureTapType)
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                            Text(gestureSide.capitalized)
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .foregroundColor(Theme.amber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.amber.opacity(0.15))
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                        if gestureSide == "right" || gestureSide == "both" {
                            Spacer()
                        }
                    }
                }

                // Data pipeline DAG
                DataPipelineView()

                // Sensor matrix (cap + temp)
                sensorMatrixCard

                // Presence
                presenceCard

                // Biometrics (HR/BR from piezo)
                biometricsCard

                // Piezo waveform
                PiezoWaveformView()

                // Temp trend
                if !sensor.leftTempHistory.isEmpty || !sensor.rightTempHistory.isEmpty {
                    tempTrendCard
                }

                // Environment
                envCard

                // System
                systemCard

                // Sensor console moved to Status screen
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .onAppear {
            sensor.piezoLeft.removeAll()
            sensor.piezoRight.removeAll()
            sensor.connect()
            livePulse = true
        }
        .onDisappear { sensor.disconnect() }
        .onChange(of: sensor.lastGesture?.ts) { _, newTs in
            guard newTs != nil, let g = sensor.lastGesture else { return }
            gestureSide = g.side
            gestureTapType = g.tapType
            withAnimation(.spring(duration: 0.3)) { showGestureBadge = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.4)) { showGestureBadge = false }
            }
        }
    }

    // MARK: - Sensor Matrix Card

    private var sensorMatrixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.accent)
                Text("SENSOR MATRIX")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }

            HStack {
                Text("LEFT")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(Theme.accent)
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                Spacer().frame(width: 36)
                Text("RIGHT")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(Color(hex: "40e0d0"))
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
            }

            BedMatrixView(
                leftPresence: sensor.leftPresence,
                rightPresence: sensor.rightPresence,
                leftVariance: sensor.leftVariance,
                rightVariance: sensor.rightVariance,
                leftTemps: sensor.leftTemps,
                rightTemps: sensor.rightTemps
            )
        }
        .cardStyle()
    }

    // MARK: - Presence Card (center-label layout like matrix)

    private var presenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill.viewfinder")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.purple)
                Text("BED PRESENCE")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }

            // Status row
            HStack {
                presenceStatus(.left, color: Theme.accent)
                    .frame(maxWidth: .infinity)
                Spacer().frame(width: 36)
                presenceStatus(.right, color: Color(hex: "40e0d0"))
                    .frame(maxWidth: .infinity)
            }

            // Zone activity — center labels like sensor matrix
            VStack(spacing: 3) {
                presenceZoneRow(zone: 0, label: "Head", icon: "brain.head.profile")
                presenceZoneRow(zone: 1, label: "Torso", icon: "figure.stand")
                presenceZoneRow(zone: 2, label: "Legs", icon: "figure.walk")
            }
        }
        .cardStyle()
    }

    private func presenceStatus(_ side: Side, color: Color) -> some View {
        let occupied = sensor.isOccupied(side: side)
        return HStack(spacing: 4) {
            Circle()
                .fill(occupied ? color : Theme.textMuted.opacity(0.2))
                .frame(width: 6, height: 6)
                .shadow(color: occupied ? color.opacity(0.6) : .clear, radius: 4)
            Text(side.displayName)
                .font(.caption2.weight(.bold))
                .foregroundColor(occupied ? color : Theme.textMuted)
            Text(occupied ? "Occupied" : "Empty")
                .font(.system(size: 8))
                .foregroundColor(Theme.textMuted)
        }
    }

    private func presenceZoneRow(zone: Int, label: String, icon: String) -> some View {
        let leftVar = max(sensor.leftVariance[safe: zone * 2] ?? 0,
                          sensor.leftVariance[safe: zone * 2 + 1] ?? 0)
        let rightVar = max(sensor.rightVariance[safe: zone * 2] ?? 0,
                           sensor.rightVariance[safe: zone * 2 + 1] ?? 0)

        return HStack(spacing: 0) {
            // Left activity bar
            activityBar(value: leftVar, color: Theme.accent, trailing: true)

            // Center label
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textMuted)
                Text(label)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(width: 36)

            // Right activity bar
            activityBar(value: rightVar, color: Color(hex: "40e0d0"), trailing: false)
        }
        .frame(height: 20)
    }

    private func activityBar(value: Float, color: Color, trailing: Bool) -> some View {
        let pct = min(Double(value) / 0.5, 1.0)
        return GeometryReader { geo in
            ZStack(alignment: trailing ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.textMuted.opacity(0.06))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(pct > 0.05 ? 0.2 + pct * 0.6 : 0.03))
                    .frame(width: geo.size.width * pct)
            }
        }
        .overlay(alignment: trailing ? .leading : .trailing) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 7).monospaced())
                .foregroundColor(pct > 0.1 ? color : Theme.textMuted)
                .padding(.horizontal, 3)
        }
    }

    // MARK: - Biometrics Card (split layout)

    private var biometricsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.error)
                Text("BED BIOMETRICS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }

            HStack(spacing: 12) {
                vitalsSide(.left, color: Theme.accent)

                Rectangle()
                    .fill(Theme.cardBorder)
                    .frame(width: 1)
                    .padding(.vertical, 4)

                vitalsSide(.right, color: Color(hex: "40e0d0"))
            }
        }
        .cardStyle()
    }

    private func vitalsSide(_ side: Side, color: Color) -> some View {
        let vitals = side == .left ? sensor.leftVitals : sensor.rightVitals
        // Use same threshold for display as for presence
        let hasSignal = vitals.confidence > 0.15

        return VStack(spacing: 6) {
            Text(side.displayName)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)

            vitalItem(icon: "heart.fill", color: Theme.error,
                      value: hasSignal ? (vitals.heartRate.map { "\(Int($0))" } ?? "--") : "--",
                      unit: "BPM")
            vitalItem(icon: "lungs.fill", color: Theme.healthy,
                      value: hasSignal ? (vitals.breathingRate.map { "\(Int($0))" } ?? "--") : "--",
                      unit: "BR")

            // Confidence
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.textMuted.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(vitals.confidence > 0.5 ? Theme.healthy : Theme.amber)
                        .frame(width: geo.size.width * vitals.confidence)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private func vitalItem(icon: String, color: Color, value: String, unit: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(value == "--" ? color.opacity(0.3) : color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(value == "--" ? Theme.textMuted : .white)
                .frame(width: 28, alignment: .trailing)
            Text(unit)
                .font(.system(size: 8))
                .foregroundColor(Theme.textMuted)
        }
    }

    // MARK: - Temp Trend Card

    private var tempTrendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.amber)
                Text("TEMPERATURE TREND")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }

            Chart {
                ForEach(Array(sensor.leftTempHistory.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Time", point.0), y: .value("°F", point.1))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .symbol { Circle().fill(Theme.accent).frame(width: 3, height: 3) }
                }
                ForEach(Array(sensor.rightTempHistory.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Time", point.0), y: .value("°F", point.1))
                        .foregroundStyle(Color(hex: "40e0d0"))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .symbol { Circle().fill(Color(hex: "40e0d0")).frame(width: 3, height: 3) }
                }
            }
            .transaction { $0.animation = nil }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Theme.cardBorder)
                    AxisValueLabel()
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(height: 100)

            HStack(spacing: 12) {
                legendDot(color: Theme.accent, label: "Left")
                legendDot(color: Color(hex: "40e0d0"), label: "Right")
            }
            .frame(maxWidth: .infinity)
        }
        .cardStyle()
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 8)).foregroundColor(Theme.textMuted)
        }
    }

    // MARK: - Environment Card

    private var envCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.cooling)
                Text("ENVIRONMENT")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }

            HStack(spacing: 0) {
                envItem(icon: "humidity.fill", color: Theme.cooling,
                        value: validHumidity(sensor.leftTemps), label: "Humidity L")
                envItem(icon: "thermometer.sun", color: Theme.amber,
                        value: validAmbient(sensor.leftTemps), label: "Ambient L")
                envItem(icon: "humidity.fill", color: Theme.cooling,
                        value: validHumidity(sensor.rightTemps), label: "Humidity R")
                envItem(icon: "thermometer.sun", color: Theme.amber,
                        value: validAmbient(sensor.rightTemps), label: "Ambient R")
            }
        }
        .cardStyle()
    }

    private func validHumidity(_ temps: BedTempSide?) -> String {
        guard let t = temps, t.hu > 0, t.hu < 100 else { return "--" }
        return "\(Int(t.hu))%"
    }

    private func validAmbient(_ temps: BedTempSide?) -> String {
        guard let t = temps, t.amb > -100 else { return "--" }
        return "\(Int(t.amb))°C"
    }

    private func envItem(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(value == "--" ? color.opacity(0.3) : color)
            Text(value)
                .font(.system(size: 10, weight: .medium).monospaced())
                .foregroundColor(value == "--" ? Theme.textMuted : .white)
                .frame(width: 36)
            Text(label)
                .font(.system(size: 7))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - System Card

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                Text("SYSTEM")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }

            if let frz = sensor.frzHealth {
                HStack(spacing: 0) {
                    sysItem(icon: "bolt.fill", color: Theme.amber,
                            value: String(format: "%.1fA", frz.left.tec.current), label: "TEC L")
                    sysItem(icon: "bolt.fill", color: Theme.amber,
                            value: String(format: "%.1fA", frz.right.tec.current), label: "TEC R")

                    sysItem(icon: "drop.fill", color: Theme.cooling,
                            value: "\(frz.left.pump.rpm ?? 0)", label: "Pump L",
                            animate: (frz.left.pump.rpm ?? 0) > 0)
                    sysItem(icon: "drop.fill", color: Theme.cooling,
                            value: "\(frz.right.pump.rpm ?? 0)", label: "Pump R",
                            animate: (frz.right.pump.rpm ?? 0) > 0)

                    if let top = frz.fan?.top {
                        VStack(spacing: 2) {
                            Image(systemName: "fan.fill")
                                .font(.system(size: 14))
                                .foregroundColor(top.rpm > 0 ? Theme.healthy : Theme.textMuted)
                                .rotationEffect(.degrees(fanRotation))
                                .onAppear {
                                    if top.rpm > 0 {
                                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                            fanRotation = 360
                                        }
                                    }
                                }
                            Text("\(top.rpm)")
                                .font(.system(size: 10, weight: .medium).monospaced())
                                .foregroundColor(.white)
                                .frame(width: 36)
                            Text("Fan")
                                .font(.system(size: 7))
                                .foregroundColor(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 2) {
                        let hasWater = frz.left.pump.water ?? true
                        Image(systemName: hasWater ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(hasWater ? Theme.healthy : Theme.error)
                        Text(hasWater ? "OK" : "Low")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(hasWater ? Theme.healthy : Theme.error)
                            .frame(width: 36)
                        Text("Water")
                            .font(.system(size: 7))
                            .foregroundColor(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 0) {
                    sysItem(icon: "bolt.fill", color: Theme.amber, value: "--", label: "TEC")
                    sysItem(icon: "drop.fill", color: Theme.cooling, value: "--", label: "Pump")
                    sysItem(icon: "fan.fill", color: Theme.healthy, value: "--", label: "Fan")
                    sysItem(icon: "checkmark.circle", color: Theme.textMuted, value: "--", label: "Water")
                }
            }
        }
        .cardStyle()
    }

    private func sysItem(icon: String, color: Color, value: String, label: String, animate: Bool = false) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(value == "--" ? color.opacity(0.3) : color)
                .symbolEffect(.pulse, isActive: animate)
            Text(value)
                .font(.system(size: 10, weight: .medium).monospaced())
                .foregroundColor(value == "--" ? Theme.textMuted : .white)
                .frame(width: 36)
            Text(label)
                .font(.system(size: 7))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Connection Bar

    private var connectionBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sensor.isConnected ? Theme.healthy : Theme.error)
                .frame(width: 7, height: 7)
                .shadow(color: sensor.isConnected ? Theme.healthy.opacity(livePulse ? 0.8 : 0) : .clear,
                        radius: livePulse ? 8 : 0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: livePulse)

            Text(sensor.isConnected ? "Live" : (sensor.error ?? "Disconnected"))
                .font(.caption.weight(.semibold))
                .foregroundColor(sensor.isConnected ? Theme.healthy : Theme.error)

            Spacer()

            if sensor.framesPerSecond > 0 {
                Text("\(sensor.framesPerSecond) fps")
                    .font(.system(size: 9).monospaced())
                    .foregroundColor(Theme.textMuted)
            }

            if let time = sensor.lastFrameTime {
                Text(time, style: .relative)
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "0a0a14"))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(sensor.isConnected ? Theme.healthy.opacity(0.2) : Theme.error.opacity(0.2), lineWidth: 1)
        )
    }
}
