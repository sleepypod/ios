import SwiftUI

/// The schedule curve from the source: each set point holds until the next, easing into it over
/// at most an hour, stroked with the app's only gradient (cool → warm).
struct TemperatureCurve: View {
    let points: [RunOnceSetPoint]
    let bedtime: String
    let wake: String
    var bedTemperature: Int = TemperatureConversion.baseTempF
    var compact = false

    private var start: Int { DisplayTime.minutes(bedtime) }
    private func offset(_ time: String) -> Int { (DisplayTime.minutes(time) - start + 1440) % 1440 }
    private var sorted: [(minute: Int, temp: Double)] {
        points.map { (offset($0.time), $0.temperature) }.sorted { $0.minute < $1.minute }
    }
    private var duration: Int {
        max(1, (DisplayTime.minutes(wake) - start + 1440) % 1440, sorted.last?.minute ?? 0)
    }

    private var domain: ClosedRange<Double> {
        var temps = sorted.map(\.temp)
        if !compact { temps.append(Double(bedTemperature)) }
        let lo = temps.min() ?? 70, hi = temps.max() ?? 84
        let span = max(hi - lo, 8)
        let pad = span * (compact ? 0.2 : 0.6)
        return (lo - pad)...(hi + pad)
    }

    private let inset: CGFloat = 5

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    if !compact {
                        Path { path in
                            let y = yPosition(Double(bedTemperature), height: size.height)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        .stroke(Theme.text3, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                    curvePath(in: size)
                        .stroke(LinearGradient(colors: [Theme.cool, Theme.warm], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: compact ? 2 : 2.5, lineCap: .round, lineJoin: .round))
                    if !compact {
                        ForEach(Array(sorted.enumerated()), id: \.offset) { _, point in
                            Circle().fill(TempColor.forScheduled(Int(point.temp)))
                                .frame(width: 8, height: 8)
                                .position(x: xPosition(point.minute, width: size.width),
                                          y: yPosition(point.temp, height: size.height))
                        }
                    }
                }
            }
            .frame(height: compact ? 56 : 130)
            if !compact {
                HStack {
                    Text(DisplayTime.tick(minutes: start))
                    Spacer()
                    Text(DisplayTime.tick(minutes: midpoint))
                    Spacer()
                    Text(DisplayTime.tick(minutes: start + duration))
                }
                .font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temperature schedule from \(DisplayTime.clock(bedtime)) to \(DisplayTime.clock(wake))")
    }

    /// Midpoint rounded to the nearest hour, as the source labels it ("2 AM").
    private var midpoint: Int {
        let raw = start + duration / 2
        return Int((Double(raw) / 60).rounded()) * 60
    }

    private func xPosition(_ minute: Int, width: CGFloat) -> CGFloat {
        let usable = width - (compact ? 0 : inset * 2)
        return (compact ? 0 : inset) + usable * CGFloat(minute) / CGFloat(duration)
    }

    private func yPosition(_ temp: Double, height: CGFloat) -> CGFloat {
        let d = domain
        return height * CGFloat((d.upperBound - temp) / (d.upperBound - d.lowerBound))
    }

    private func curvePath(in size: CGSize) -> Path {
        Path { path in
            guard let first = sorted.first else { return }
            let ramp = 60
            path.move(to: CGPoint(x: xPosition(0, width: size.width), y: yPosition(first.temp, height: size.height)))
            var previous = (minute: 0, temp: first.temp)
            for point in sorted {
                let y0 = yPosition(previous.temp, height: size.height)
                let y1 = yPosition(point.temp, height: size.height)
                let rampStart = max(previous.minute, point.minute - ramp)
                if rampStart > previous.minute {
                    path.addLine(to: CGPoint(x: xPosition(rampStart, width: size.width), y: y0))
                }
                let x0 = xPosition(rampStart, width: size.width)
                let x1 = xPosition(point.minute, width: size.width)
                if x1 > x0 && abs(y1 - y0) > 0.5 {
                    let w = x1 - x0
                    path.addCurve(to: CGPoint(x: x1, y: y1),
                                  control1: CGPoint(x: x0 + w * 0.5, y: y0),
                                  control2: CGPoint(x: x0 + w * 0.7, y: y1))
                } else {
                    path.addLine(to: CGPoint(x: x1, y: y1))
                }
                previous = point
            }
            path.addLine(to: CGPoint(x: xPosition(duration, width: size.width) + (compact ? 0 : inset),
                                     y: yPosition(previous.temp, height: size.height)))
        }
    }
}
