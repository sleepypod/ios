import SwiftUI

struct PiezoWaveformView: View {
    @Environment(SensorStreamService.self) private var sensor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path")
                    .font(.caption)
                    .foregroundColor(Theme.accent)
                Text("PIEZO WAVEFORM")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
                Spacer()
                HStack(spacing: 8) {
                    legendDot(color: Color(hex: "4a9eff"), label: "Left")
                    legendDot(color: Color(hex: "40e0d0"), label: "Right")
                }
            }

            // Snapshot on main thread — Canvas closure captures these value types
            let left = sensor.piezoLeft
            let right = sensor.piezoRight
            scopeCanvas(left: left, right: right)
                .frame(height: 130)
                .allowsHitTesting(false)
        }
        .padding(12)
        .background(Color(hex: "020208"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "1a2a3a").opacity(0.5), lineWidth: 1)
        )
    }

    private func scopeCanvas(left: [Int32], right: [Int32]) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard w > 0, h > 0 else { return }

            drawGrid(context: context, w: w, h: h)

            guard !left.isEmpty || !right.isEmpty else { return }

            let (rMin, rMax) = sharedRange(left, right)
            let range = rMax - rMin
            guard range > 0, range.isFinite else { return }

            if let path = tracePath(left, w: w, h: h, rMin: rMin, range: range) {
                let c = Color(hex: "4a9eff")
                context.stroke(path, with: .color(c.opacity(0.08)), lineWidth: 6)
                context.stroke(path, with: .color(c.opacity(0.3)), lineWidth: 2.5)
                context.stroke(path, with: .color(c), lineWidth: 0.8)
            }
            if let path = tracePath(right, w: w, h: h, rMin: rMin, range: range) {
                let c = Color(hex: "40e0d0")
                context.stroke(path, with: .color(c.opacity(0.08)), lineWidth: 6)
                context.stroke(path, with: .color(c.opacity(0.3)), lineWidth: 2.5)
                context.stroke(path, with: .color(c), lineWidth: 0.8)
            }
        }
    }

    private func drawGrid(context: GraphicsContext, w: CGFloat, h: CGFloat) {
        let minor = Color(hex: "0a1018")
        let major = Color(hex: "0f1a2a")

        let cols = max(1, Int(w / 25))
        for i in 1..<cols {
            let x = w * CGFloat(i) / CGFloat(cols)
            var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
            context.stroke(p, with: .color(minor), lineWidth: 0.5)
        }
        for i in 1..<8 {
            let y = h * CGFloat(i) / 8
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
            context.stroke(p, with: .color(minor), lineWidth: 0.5)
        }

        var hc = Path(); hc.move(to: CGPoint(x: 0, y: h / 2)); hc.addLine(to: CGPoint(x: w, y: h / 2))
        context.stroke(hc, with: .color(major), lineWidth: 0.8)
        var vc = Path(); vc.move(to: CGPoint(x: w / 2, y: 0)); vc.addLine(to: CGPoint(x: w / 2, y: h))
        context.stroke(vc, with: .color(major), lineWidth: 0.8)
    }

    private func sharedRange(_ a: [Int32], _ b: [Int32]) -> (Float, Float) {
        var lo: Float = .greatestFiniteMagnitude
        var hi: Float = -.greatestFiniteMagnitude
        for s in a { let f = Float(s); if f < lo { lo = f }; if f > hi { hi = f } }
        for s in b { let f = Float(s); if f < lo { lo = f }; if f > hi { hi = f } }
        guard lo < hi else { return (0, 1) }
        let pad = (hi - lo) * 0.1
        return (lo - pad, hi + pad)
    }

    private func tracePath(_ samples: [Int32], w: CGFloat, h: CGFloat, rMin: Float, range: Float) -> Path? {
        guard samples.count > 20 else { return nil }

        let target = 200
        let step = max(1, samples.count / target)
        let n = samples.count / step
        guard n >= 2 else { return nil }

        var pts = [CGPoint]()
        pts.reserveCapacity(n)
        for i in 0..<n {
            let lo = i * step
            let hi = min(lo + step, samples.count)
            var sum: Int64 = 0
            for j in lo..<hi { sum += Int64(samples[j]) }
            let avg = Float(sum) / Float(hi - lo)
            let norm = (avg - rMin) / range
            let x = w * CGFloat(i) / CGFloat(n - 1)
            let y = h * (1 - CGFloat(norm))
            guard x.isFinite, y.isFinite else { continue }
            pts.append(CGPoint(x: x, y: min(max(y, 0), h)))
        }
        guard pts.count >= 2 else { return nil }

        var path = Path()
        path.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let cp1x = p1.x + (p2.x - p0.x) / 6
            let cp1y = p1.y + (p2.y - p0.y) / 6
            let cp2x = p2.x - (p3.x - p1.x) / 6
            let cp2y = p2.y - (p3.y - p1.y) / 6
            if cp1x.isFinite && cp1y.isFinite && cp2x.isFinite && cp2y.isFinite {
                path.addCurve(to: p2,
                              control1: CGPoint(x: cp1x, y: cp1y),
                              control2: CGPoint(x: cp2x, y: cp2y))
            } else {
                path.addLine(to: p2)
            }
        }
        return path
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 8)).foregroundColor(Theme.textMuted)
        }
    }
}
