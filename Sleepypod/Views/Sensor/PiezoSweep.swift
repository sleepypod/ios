import CoreGraphics
import Foundation

/// Sweep-mode layout for the live piezo scope, ported from sleepypod-core's PiezoWaveform.
///
/// Like a bedside monitor, a cursor moves left to right in real time and writes over the
/// previous sweep behind a small gap, so nothing already drawn moves sideways. Buckets are
/// anchored to absolute sample numbers, so a bucket's value never changes once it is full.
enum PiezoSweep {
    /// Seconds of signal one sweep spans. The service keeps ~12 s, so a sweep plus the lag fits.
    static let sweepSeconds = 8.0
    /// How far the cursor trails the newest sample. Frames land about once a second, so the
    /// cursor needs more than a frame of runway to move without stalling.
    static let lagSeconds = 1.5
    /// Blank strip ahead of the cursor that separates new signal from the previous sweep.
    static let gapSeconds = 0.3
    /// Bucket-averaged points across the canvas.
    static let points = 200
    /// Minimum samples before a channel is drawn.
    static let minSamples = 20
    /// Vertical scale easing: grow fast so peaks stay on canvas, shrink slowly so it holds still.
    static let growTau = 0.12
    static let shrinkTau = 2.5

    /// One channel's contiguous samples; `first` is the absolute number of `samples[0]`.
    struct Channel {
        var first: Int
        var samples: [Int32]
        /// One past the newest sample.
        var end: Int { first + samples.count }
    }

    struct Geometry: Equatable {
        let points: Int
        /// Samples per bucket.
        let size: Int
        /// Buckets left blank ahead of the cursor.
        let gap: Int
        var sweep: Int { points * size }
    }

    static func geometry(hz: Double) -> Geometry {
        let size = max(1, Int((sweepSeconds * hz / Double(points)).rounded()))
        return Geometry(points: points, size: size, gap: Int((gapSeconds * hz / Double(size)).rounded(.up)))
    }

    /// Average `count` buckets of `size` samples starting at absolute bucket `firstBucket`, where
    /// bucket b covers sample numbers [b·size, (b+1)·size). Samples numbered past `maxN` are
    /// ignored; empty buckets are NaN.
    static func bucketAverages(_ ch: Channel, firstBucket: Int, count: Int, size: Int, maxN: Double = .infinity) -> [Double] {
        guard count > 0 else { return [] }
        let cap = maxN.isFinite ? Int(maxN.rounded(.down)) + 1 : Int.max
        let limit = min(ch.end, cap)
        var out = [Double](repeating: .nan, count: count)
        for k in 0..<count {
            let lo = max((firstBucket + k) * size, ch.first)
            let hi = min((firstBucket + k + 1) * size, limit)
            guard hi > lo else { continue }
            var sum: Int64 = 0
            for i in (lo - ch.first)..<(hi - ch.first) { sum += Int64(ch.samples[i]) }
            out[k] = Double(sum) / Double(hi - lo)
        }
        return out
    }

    /// Shared vertical range from the 0.5th–99.5th percentiles of samples numbered `fromN` or
    /// later, padded 15%. Percentiles keep one movement spike from squashing the rest.
    static func robustRange(_ channels: [Channel], fromN: Int) -> (lo: Double, hi: Double)? {
        var values: [Double] = []
        for ch in channels {
            let start = max(fromN, ch.first)
            guard start < ch.end else { continue }
            values.reserveCapacity(values.count + ch.end - start)
            for i in (start - ch.first)..<ch.samples.count { values.append(Double(ch.samples[i])) }
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        func at(_ q: Double) -> Double {
            values[min(values.count - 1, max(0, Int((q * Double(values.count - 1)).rounded())))]
        }
        let lo = at(0.005), hi = at(0.995)
        guard hi > lo else { return (lo - 1, lo + 1) }
        let pad = (hi - lo) * 0.15
        return (lo - pad, hi + pad)
    }

    /// Advance the cursor (a fractional absolute sample number) by `dt` seconds of real time,
    /// trimming its rate toward a fixed lag behind the newest sample. It never runs past the
    /// data, and jumps only after a long gap (backgrounding or a reconnect).
    static func advance(play: Double?, first: Int, end: Int, hz: Double, dt: Double) -> Double {
        let goal = max(Double(first), Double(end) - lagSeconds * hz)
        guard let play, abs(goal - play) <= 4 * hz else { return goal }
        let err = (goal - play) / hz
        let next = play + dt * hz * (1 + min(max(err * 0.5, -0.25), 0.25))
        return min(next, Double(end))
    }

    /// Ease the displayed range toward the target: quickly when the range grows, slowly when it shrinks.
    static func ease(shown: (lo: Double, hi: Double), target: (lo: Double, hi: Double), dt: Double) -> (lo: Double, hi: Double) {
        func step(_ from: Double, _ to: Double, grow: Bool) -> Double {
            from + (to - from) * (1 - exp(-dt / (grow ? growTau : shrinkTau)))
        }
        return (step(shown.lo, target.lo, grow: target.lo < shown.lo),
                step(shown.hi, target.hi, grow: target.hi > shown.hi))
    }

    /// Cursor position across the canvas, 0...width.
    static func cursorX(play: Double, geometry g: Geometry, width: Double) -> Double {
        let sweep = Double(g.sweep)
        return play.truncatingRemainder(dividingBy: sweep) / sweep * width
    }

    /// Drawable runs for one channel: this sweep up to the cursor (its newest point sits on the
    /// cursor itself), then the previous sweep from just past the gap to the right edge.
    /// Runs break at empty buckets.
    static func runs(_ ch: Channel, play: Double, geometry g: Geometry, width: Double, yOf: (Double) -> Double) -> [[CGPoint]] {
        let cursor = Int((play / Double(g.size)).rounded(.down))
        let passStart = cursor - cursor % g.points
        let c = cursor - passStart
        let headX = (play - Double(passStart * g.size)) / Double(g.sweep) * width
        let slot = { (k: Int) in (Double(k) + 0.5) / Double(g.points) * width }

        var out: [[CGPoint]] = []
        let current = bucketAverages(ch, firstBucket: passStart, count: c + 1, size: g.size, maxN: play)
        appendRuns(current, x: { $0 == c ? headX : slot($0) }, yOf: yOf, into: &out)

        let from = c + 1 + g.gap
        if from < g.points {
            let previous = bucketAverages(ch, firstBucket: passStart - g.points + from, count: g.points - from, size: g.size)
            appendRuns(previous, x: { slot(from + $0) }, yOf: yOf, into: &out)
        }
        return out
    }

    private static func appendRuns(_ avgs: [Double], x: (Int) -> Double, yOf: (Double) -> Double, into out: inout [[CGPoint]]) {
        var run: [CGPoint] = []
        for (k, v) in avgs.enumerated() {
            guard !v.isNaN else {
                if run.count > 1 { out.append(run) }
                run = []
                continue
            }
            run.append(CGPoint(x: x(k), y: yOf(v)))
        }
        if run.count > 1 { out.append(run) }
    }
}
