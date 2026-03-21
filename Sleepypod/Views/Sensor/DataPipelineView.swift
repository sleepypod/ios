import SwiftUI

// MARK: - Lane Configuration

private struct TimelineLane {
    let type: String
    let label: String
    let color: Color
}

private let timelineLanes: [TimelineLane] = [
    TimelineLane(type: "piezo-dual", label: "PIE", color: .purple),
    TimelineLane(type: "capSense2", label: "PRE", color: Color(hex: "4ade80")),
    TimelineLane(type: "bedTemp2", label: "BED", color: .orange),
    TimelineLane(type: "frzHealth", label: "FRE", color: Color(hex: "60a5fa")),
    TimelineLane(type: "deviceStatus", label: "DEV", color: Color(hex: "38bdf8")),
    TimelineLane(type: "log", label: "LOG", color: .yellow),
    TimelineLane(type: "gesture", label: "TAP", color: .pink),
]

// MARK: - DAG Node Descriptor

private struct DAGNode: Identifiable {
    let id: String
    let label: String
    let subtitle: String
    let color: Color
    /// Normalized position (0…1) within the DAG area.
    let nx: CGFloat
    let ny: CGFloat
}

// MARK: - DAG Edge Descriptor

private struct DAGEdge: Identifiable {
    let id: String
    let from: String
    let to: String
    let color: Color
    let dashed: Bool
}

// MARK: - DataPipelineView

/// Live data pipeline DAG with node-and-edge graph and a scrolling Canvas
/// event timeline showing the last 30 seconds of frame arrivals.
struct DataPipelineView: View {
    @Environment(SensorStreamService.self) private var sensor

    @State private var previousCounts: [String: Int] = [:]
    @State private var rates: [String: Double] = [:]
    @State private var lastFrameAt: Date = .distantPast

    // MARK: - Computed

    private var totalRate: Double {
        rates.values.reduce(0, +)
    }

    private func rateString(for types: [String]) -> String {
        let r = types.compactMap { rates[$0] }.reduce(0, +)
        if r >= 1 { return String(format: "%.1f/s", r) }
        if r > 0 { return "\(Int(r * 60))/m" }
        return ""
    }

    private func isActive(_ types: [String]) -> Bool {
        types.contains { (sensor.frameCounts[$0] ?? 0) > 0 }
    }

    // MARK: - DAG Layout

    /// Build nodes dynamically so subtitles reflect live rates.
    private var dagNodes: [DAGNode] {
        let wsLabel = sensor.isConnected ? "connected" : "disconnected"
        let piezoRate = rateString(for: ["piezo-dual"])
        let dacRate = rateString(for: ["deviceStatus", "frzHealth", "frzTemp", "frzTherm"])

        return [
            // Row 0 — Firmware
            DAGNode(id: "firmware", label: "Firmware", subtitle: "frankenfirmware",
                    color: Color(hex: "71717a"), nx: 0.5, ny: 0.0),

            // Row 1 — RAW Files + dacTransport
            DAGNode(id: "raw", label: "RAW Files", subtitle: "CBOR on disk",
                    color: Color(hex: "71717a"), nx: 0.18, ny: 0.2),
            DAGNode(id: "dac-transport", label: "dacTransport", subtitle: "dac.sock",
                    color: Color(hex: "a1a1aa"), nx: 0.5, ny: 0.2),

            // Row 2 — piezoStream + DacMonitor + tRPC
            DAGNode(id: "piezo-stream", label: "piezoStream", subtitle: piezoRate.isEmpty ? "tails + parses" : "parse · \(piezoRate)",
                    color: Color(hex: "8b5cf6"), nx: 0.18, ny: 0.4),
            DAGNode(id: "dac-monitor", label: "DacMonitor", subtitle: dacRate.isEmpty ? "polls 2s" : "poll · \(dacRate)",
                    color: Color(hex: "3b82f6"), nx: 0.5, ny: 0.4),
            DAGNode(id: "trpc", label: "tRPC", subtitle: "mutations",
                    color: Color(hex: "f97316"), nx: 0.82, ny: 0.4),

            // Row 3 — WebSocket
            DAGNode(id: "ws", label: "WebSocket :3001", subtitle: wsLabel,
                    color: sensor.isConnected ? Color(hex: "22c55e") : Theme.error,
                    nx: 0.38, ny: 0.65),

            // Row 4 — Browser/App
            DAGNode(id: "browser", label: "iOS App", subtitle: "SwiftUI",
                    color: .white, nx: 0.5, ny: 0.88),
        ]
    }

    private var dagEdges: [DAGEdge] {
        let wsColor = sensor.isConnected ? Color(hex: "22c55e") : Theme.error
        return [
            // Read path (↓) — solid
            DAGEdge(id: "fw-raw", from: "firmware", to: "raw", color: Color(hex: "52525b"), dashed: false),
            DAGEdge(id: "fw-dt", from: "firmware", to: "dac-transport", color: Color(hex: "a1a1aa"), dashed: false),
            DAGEdge(id: "raw-ps", from: "raw", to: "piezo-stream", color: Color(hex: "8b5cf6"), dashed: false),
            DAGEdge(id: "dt-dm", from: "dac-transport", to: "dac-monitor", color: Color(hex: "3b82f6"), dashed: false),
            DAGEdge(id: "ps-ws", from: "piezo-stream", to: "ws", color: Color(hex: "8b5cf6"), dashed: false),
            DAGEdge(id: "dm-ws", from: "dac-monitor", to: "ws", color: Color(hex: "3b82f6"), dashed: false),
            DAGEdge(id: "ws-browser", from: "ws", to: "browser", color: wsColor, dashed: false),

            // Write path (↑) — dashed orange
            DAGEdge(id: "browser-trpc", from: "browser", to: "trpc", color: Color(hex: "f97316"), dashed: true),
            DAGEdge(id: "trpc-dt", from: "trpc", to: "dac-transport", color: Color(hex: "f97316"), dashed: true),
        ]
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            dagView
            timelineSection
        }
        .cardStyle()
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            for (type, count) in sensor.frameCounts {
                let prev = previousCounts[type] ?? count
                let delta = count - prev
                rates[type] = Double(delta) / 2.0
                previousCounts[type] = count
            }
        }
        .onChange(of: sensor.lastFrameTime) { _, newTime in
            if let t = newTime { lastFrameAt = t }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Data Pipeline")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 8) {
                legendBadge(label: "read ↓", color: Color(hex: "60a5fa"))
                legendBadge(label: "write ↑", color: Color(hex: "f97316"))
            }
        }
    }

    private func legendBadge(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 10, height: 1)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Theme.textMuted)
        }
    }

    // MARK: - DAG View

    private var dagView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let nodeMap = Dictionary(uniqueKeysWithValues: dagNodes.map { ($0.id, $0) })

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "0a0a0a"))

                // Dot grid background
                Canvas { ctx, size in
                    let dotGap: CGFloat = 20
                    for x in stride(from: dotGap, to: size.width, by: dotGap) {
                        for y in stride(from: dotGap, to: size.height, by: dotGap) {
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1)),
                                with: .color(Color.white.opacity(0.06))
                            )
                        }
                    }
                }

                // Edges — SwiftUI Path views with animated dash phase
                ForEach(dagEdges) { edge in
                    if let fromNode = nodeMap[edge.from],
                       let toNode = nodeMap[edge.to] {
                        AnimatedEdge(
                            from: CGPoint(x: fromNode.nx * w, y: fromNode.ny * h + 14),
                            to: CGPoint(x: toNode.nx * w, y: toNode.ny * h - 6),
                            color: edge.color,
                            dashed: edge.dashed,
                            isActive: sensor.isConnected
                        )
                    }
                }

                // Nodes
                ForEach(dagNodes) { node in
                    let x = node.nx * w
                    let y = node.ny * h
                    let active = isNodeActive(node.id)

                    PipelineNodeView(
                        label: node.label,
                        subtitle: node.subtitle,
                        color: node.color,
                        active: active
                    )
                    .position(x: x, y: y)
                }
            }
        }
        .frame(height: 260)
    }

    private func isNodeActive(_ id: String) -> Bool {
        switch id {
        case "firmware": return sensor.isConnected
        case "raw": return isActive(["piezo-dual"])
        case "dac-transport": return sensor.isConnected
        case "piezo-stream": return isActive(["piezo-dual"])
        case "dac-monitor": return isActive(["deviceStatus", "frzHealth", "frzTemp", "frzTherm"])
        case "trpc": return sensor.isConnected
        case "ws": return sensor.isConnected
        case "browser": return sensor.isConnected
        default: return false
        }
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Text(String(format: "%.1f", totalRate))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white)
                Text("/s total · 30s window")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(alignment: .top, spacing: 4) {
                // Lane labels
                VStack(spacing: 0) {
                    ForEach(Array(timelineLanes.enumerated()), id: \.offset) { _, lane in
                        Text(lane.label)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(lane.color.opacity(0.7))
                            .frame(height: 16, alignment: .center)
                    }
                }
                .frame(width: 24)

                // Timeline Canvas
                ZStack(alignment: .bottomTrailing) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                        Canvas { context, size in
                            let now = timeline.date.timeIntervalSince1970
                            let windowSec: Double = 30
                            let laneCount = timelineLanes.count
                            let laneHeight = size.height / CGFloat(laneCount)

                            // Background
                            context.fill(
                                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                                with: .color(Color.black.opacity(0.4))
                            )

                            // Lane separators
                            for i in 1..<laneCount {
                                let y = CGFloat(i) * laneHeight
                                var sep = Path()
                                sep.move(to: CGPoint(x: 0, y: y))
                                sep.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(sep, with: .color(Color.white.opacity(0.03)), lineWidth: 0.5)
                            }

                            // Time markers at -10s and -20s
                            for sec in [10.0, 20.0] {
                                let x = size.width * CGFloat(1.0 - sec / windowSec)
                                var markerPath = Path()
                                markerPath.move(to: CGPoint(x: x, y: 0))
                                markerPath.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(markerPath, with: .color(Color.white.opacity(0.05)), lineWidth: 0.5)

                                context.draw(
                                    Text("-\(Int(sec))s")
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundColor(Color.white.opacity(0.12)),
                                    at: CGPoint(x: x + 10, y: size.height - 5)
                                )
                            }

                            // Event dots
                            for (laneIndex, lane) in timelineLanes.enumerated() {
                                let y = CGFloat(laneIndex) * laneHeight + laneHeight / 2

                                for frame in sensor.recentFrames where frame.type == lane.type {
                                    let age = now - frame.timestamp.timeIntervalSince1970
                                    if age > windowSec || age < 0 { continue }
                                    let x = size.width * CGFloat(1.0 - age / windowSec)
                                    let alpha = max(0.15, 1.0 - age / windowSec * 0.8)

                                    // Glow for very recent
                                    if age < 0.5 {
                                        context.fill(
                                            Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                                            with: .color(lane.color.opacity(0.3))
                                        )
                                    }

                                    context.fill(
                                        Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)),
                                        with: .color(lane.color.opacity(alpha))
                                    )
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(timelineLanes.count) * 16)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("30s")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                        .padding(.trailing, 6)
                        .padding(.bottom, 3)
                }
            }
        }
    }
}

// MARK: - Pipeline Node View

private struct PipelineNodeView: View {
    let label: String
    let subtitle: String
    let color: Color
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "0a0a0a"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(active ? color.opacity(0.4) : Color(hex: "333333").opacity(0.6), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            // Colored left border accent
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(active ? 0.8 : 0.2))
                .frame(width: active ? 3 : 1)
                .padding(.vertical, 2)
        }
        .shadow(color: active ? color.opacity(0.15) : .clear, radius: 4, x: 0, y: 0)
    }
}

// MARK: - Animated Edge (dot traveling along path via trim)

private struct BezierEdge: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        let midY = (from.y + to.y) / 2
        p.addCurve(to: to, control1: CGPoint(x: from.x, y: midY), control2: CGPoint(x: to.x, y: midY))
        return p
    }
}

private struct AnimatedEdge: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let dashed: Bool
    let isActive: Bool

    @State private var trimEnd: CGFloat = 0

    var body: some View {
        ZStack {
            // Static dim baseline
            BezierEdge(from: from, to: to)
                .stroke(
                    color.opacity(isActive ? 0.15 : 0.06),
                    style: StrokeStyle(
                        lineWidth: 0.5,
                        dash: dashed ? [4, 3] : []
                    )
                )

            // Animated dot traveling along the path
            if isActive {
                BezierEdge(from: from, to: to)
                    .trim(from: max(0, trimEnd - 0.08), to: trimEnd)
                    .stroke(
                        color.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
            }
        }
        .onAppear {
            guard isActive else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                trimEnd = 1
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                trimEnd = 0
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    trimEnd = 1
                }
            }
        }
    }
}
