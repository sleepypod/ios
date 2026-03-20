import SwiftUI

/// Live data pipeline DAG with pulsing edges and scrolling event timeline.
/// Shows: Firmware → WebSocket → consumer buckets, with per-type frame rates
/// and colored pulses as data flows through.
struct DataPipelineView: View {
    @Environment(SensorStreamService.self) private var sensor

    private static let consumers: [(key: String, label: String, color: Color, types: [String])] = [
        ("piezo", "Piezo", Color(hex: "a78bfa"), ["piezo-dual"]),
        ("presence", "Presence", Color(hex: "4ade80"), ["capSense", "capSense2"]),
        ("bedTemp", "Bed Temp", Color(hex: "fb923c"), ["bedTemp", "bedTemp2"]),
        ("freezer", "Freezer", Color(hex: "60a5fa"), ["frzTemp", "frzHealth", "frzTherm"]),
        ("status", "Device", Color(hex: "38bdf8"), ["deviceStatus"]),
        ("log", "Log", Color(hex: "fbbf24"), ["log"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("DATA PIPELINE")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
                Spacer()
                Text("\(sensor.framesPerSecond)/s total")
                    .font(.system(size: 9).monospaced())
                    .foregroundColor(Theme.textMuted)
            }

            // Source row
            HStack(spacing: 6) {
                Spacer()
                PipeNode(label: "Firmware", sub: "dac.sock + RAW", color: Theme.textMuted)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textMuted)
                PipeNode(
                    label: "WebSocket",
                    sub: ":3001 · \(sensor.isConnected ? "connected" : "disconnected")",
                    color: sensor.isConnected ? Theme.healthy : Theme.error,
                    pulse: sensor.isConnected
                )
                Spacer()
            }

            // Fan-out edges (simplified — vertical lines per consumer)
            GeometryReader { geo in
                let count = Self.consumers.count
                let spacing = geo.size.width / CGFloat(count)

                Canvas { ctx, size in
                    // Trunk
                    let centerX = size.width / 2
                    ctx.stroke(
                        Path { p in p.move(to: CGPoint(x: centerX, y: 0)); p.addLine(to: CGPoint(x: centerX, y: 4)) },
                        with: .color(Theme.cardBorder), lineWidth: 1
                    )
                    // Rail
                    let railY: CGFloat = 4
                    ctx.stroke(
                        Path { p in p.move(to: CGPoint(x: spacing * 0.5, y: railY)); p.addLine(to: CGPoint(x: size.width - spacing * 0.5, y: railY)) },
                        with: .color(Theme.cardBorder), lineWidth: 1
                    )
                    // Drop lines + pulse
                    for (i, consumer) in Self.consumers.enumerated() {
                        let x = spacing * (CGFloat(i) + 0.5)
                        let count = consumer.types.reduce(0) { $0 + (sensor.frameCounts[$1] ?? 0) }
                        let hasRecent = count > 0

                        // Base drop line
                        ctx.stroke(
                            Path { p in p.move(to: CGPoint(x: x, y: railY)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                            with: .color(Theme.cardBorder), lineWidth: 1
                        )

                        // Pulse overlay (always visible if any frames received)
                        if hasRecent {
                            ctx.stroke(
                                Path { p in
                                    p.move(to: CGPoint(x: min(centerX, x), y: railY))
                                    p.addLine(to: CGPoint(x: max(centerX, x), y: railY))
                                },
                                with: .color(consumer.color.opacity(0.4)), lineWidth: 2
                            )
                            ctx.stroke(
                                Path { p in p.move(to: CGPoint(x: x, y: railY)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                                with: .color(consumer.color.opacity(0.6)), lineWidth: 2
                            )
                            // Glow dot at bottom
                            ctx.fill(
                                Circle().path(in: CGRect(x: x - 3, y: size.height - 3, width: 6, height: 6)),
                                with: .color(consumer.color.opacity(0.3))
                            )
                        }
                    }
                }
            }
            .frame(height: 20)

            // Consumer nodes
            HStack(spacing: 2) {
                ForEach(Self.consumers, id: \.key) { consumer in
                    let count = consumer.types.reduce(0) { $0 + (sensor.frameCounts[$1] ?? 0) }
                    PipeNode(
                        label: consumer.label,
                        sub: count > 0 ? "\(count)" : "—",
                        color: consumer.color,
                        pulse: count > 0,
                        small: true
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            // Scrolling timeline (simplified — show last-frame timestamps per type)
            HStack(spacing: 0) {
                ForEach(Self.consumers, id: \.key) { consumer in
                    let hasData = consumer.types.contains { sensor.frameCounts[$0] ?? 0 > 0 }
                    Circle()
                        .fill(hasData ? consumer.color : consumer.color.opacity(0.1))
                        .frame(width: 4, height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
        .cardStyle()
    }
}

// MARK: - Pipeline Node

private struct PipeNode: View {
    let label: String
    let sub: String
    let color: Color
    var pulse: Bool = false
    var small: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: small ? 8 : 9, weight: .medium))
                .foregroundColor(color)
            Text(sub)
                .font(.system(size: small ? 7 : 8))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, small ? 4 : 8)
        .padding(.vertical, small ? 3 : 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(pulse ? 0.4 : 0.15), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(pulse ? color.opacity(0.08) : .clear)
                )
        )
    }
}
