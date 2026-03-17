import SwiftUI

/// Combined cap + temp matrix for both sides with center labels.
/// 3 zones (Head/Torso/Legs) — REF hidden (used internally for baseline).
struct BedMatrixView: View {
    let leftPresence: CapSenseSide?
    let rightPresence: CapSenseSide?
    let leftVariance: [Float]
    let rightVariance: [Float]
    let leftTemps: BedTempSide?
    let rightTemps: BedTempSide?

    @State private var scanOffset: CGFloat = 0

    private static let zoneLabels = ["Head", "Torso", "Legs"]
    private static let zoneIcons = ["brain.head.profile", "figure.stand", "figure.walk"]

    var body: some View {
        VStack(spacing: 2) {
            // Only show 3 active zones (skip REF)
            ForEach(0..<3, id: \.self) { zone in
                HStack(spacing: 0) {
                    leftCells(zone: zone)

                    // Center label column
                    VStack(spacing: 2) {
                        Image(systemName: Self.zoneIcons[zone])
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textMuted)
                        Text(Self.zoneLabels[zone])
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .frame(width: 36)

                    rightCells(zone: zone)
                }
                .frame(height: 56)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            // Scan line animation
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .overlay {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Theme.accent.opacity(0.08), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 20)
                .offset(y: scanOffset * geo.size.height)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    scanOffset = 1
                }
            }
        }
    }

    private func leftCells(zone: Int) -> some View {
        let i = zone * 2
        let temp = zoneTemp(leftTemps, zone: zone)
        let activity = maxVariance(leftVariance, zone: zone)
        return HStack(spacing: 2) {
            sensorCell(capValue: leftPresence?.values[safe: i],
                       variance: leftVariance[safe: i] ?? 0,
                       tempC: temp, activity: activity)
            sensorCell(capValue: leftPresence?.values[safe: i + 1],
                       variance: leftVariance[safe: i + 1] ?? 0,
                       tempC: temp, activity: activity)
        }
    }

    private func rightCells(zone: Int) -> some View {
        let i = zone * 2
        let temp = zoneTemp(rightTemps, zone: zone)
        let activity = maxVariance(rightVariance, zone: zone)
        return HStack(spacing: 2) {
            sensorCell(capValue: rightPresence?.values[safe: i],
                       variance: rightVariance[safe: i] ?? 0,
                       tempC: temp, activity: activity)
            sensorCell(capValue: rightPresence?.values[safe: i + 1],
                       variance: rightVariance[safe: i + 1] ?? 0,
                       tempC: temp, activity: activity)
        }
    }

    private func maxVariance(_ variance: [Float], zone: Int) -> Float {
        let i = zone * 2
        return max(variance[safe: i] ?? 0, variance[safe: i + 1] ?? 0)
    }

    private func zoneTemp(_ temps: BedTempSide?, zone: Int) -> Float? {
        guard let temps, zone < temps.temps.count else { return nil }
        let t = temps.temps[zone]
        return t > -100 ? t : nil
    }

    private func sensorCell(capValue: Float?, variance: Float, tempC: Float?, activity: Float) -> some View {
        let cap = capValue ?? 0
        let actNorm = min(Double(activity) / 0.3, 1.0)

        return ZStack {
            // Background: temp color if available, otherwise cap
            if let tempC {
                Rectangle().fill(tempColor(tempC))
            } else {
                Rectangle().fill(capColor(cap))
            }

            // Activity glow — neon pulse
            if actNorm > 0.03 {
                Rectangle()
                    .fill(Theme.accent.opacity(actNorm * 0.7))
                    .blur(radius: 2)
            }

            // Values — fixed width to prevent shifting
            VStack(spacing: 1) {
                if let tempC {
                    let f = tempC * 9.0 / 5.0 + 32
                    Text("\(Int(f))°")
                        .font(.system(size: 12, weight: .bold).monospaced())
                        .foregroundColor(.white)
                        .frame(width: 36)
                } else {
                    Text("--°")
                        .font(.system(size: 12, weight: .bold).monospaced())
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 36)
                }

                Text(String(format: "%05.1f", cap))
                    .font(.system(size: 7).monospaced())
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 36)

                Text(variance > 0.01 ? String(format: "±%04.2f", variance) : "±0.00")
                    .font(.system(size: 6).monospaced())
                    .foregroundColor(actNorm > 0.1 ? Theme.accent : .white.opacity(0.2))
                    .frame(width: 36)
            }
        }
        .overlay(
            // Active cell border glow
            actNorm > 0.15 ?
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.accent.opacity(actNorm * 0.5), lineWidth: 1) : nil
        )
    }

    // MARK: - Colors

    private func tempColor(_ celsius: Float) -> Color {
        let t = max(18, min(38, celsius))
        let normalized = (t - 18) / 20 // 0 at 18°C, 1 at 38°C

        if normalized < 0.3 {
            // Cool: deep blue
            return Color(hex: "0a2a6c").opacity(0.5 + Double(normalized) * 1.5)
        } else if normalized < 0.5 {
            // Neutral: teal
            return Color(hex: "0a4a5c").opacity(0.5 + Double(normalized))
        } else if normalized < 0.7 {
            // Warm: amber
            return Color(hex: "5a4a1a").opacity(0.5 + Double(normalized) * 0.5)
        } else {
            // Hot: deep orange
            return Color(hex: "6a2a0a").opacity(0.6 + Double(normalized) * 0.4)
        }
    }

    private func capColor(_ value: Float) -> Color {
        let n = min(max(Double(value) / 30.0, 0), 1.0)
        if n < 0.3 { return Color(hex: "080818") }
        if n < 0.6 { return Color(hex: "0d2860").opacity(0.4 + n) }
        return Color(hex: "1a4a9c").opacity(0.5 + n * 0.4)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
