import Testing
import Foundation
@testable import Sleepypod

@Suite("PiezoSweep")
struct PiezoSweepTests {

    private func channel(first: Int, count: Int, value: (Int) -> Int32 = { Int32($0) }) -> PiezoSweep.Channel {
        PiezoSweep.Channel(first: first, samples: (first..<(first + count)).map(value))
    }

    @Test("Geometry spans 8 s across 200 buckets with a 0.3 s gap")
    func geometry() {
        let g = PiezoSweep.geometry(hz: 500)
        #expect(g.points == 200)
        #expect(g.size == 20)
        #expect(g.sweep == 4000)
        #expect(g.gap == 8)
    }

    @Test("Buckets are anchored to absolute sample numbers")
    func bucketsAnchored() {
        let ch = channel(first: 10, count: 30)  // samples 10...39, value = number
        let avgs = PiezoSweep.bucketAverages(ch, firstBucket: 0, count: 4, size: 10)
        #expect(avgs[0].isNaN)
        #expect(avgs[1] == 14.5)
        #expect(avgs[2] == 24.5)
        #expect(avgs[3] == 34.5)

        // Trimming older samples doesn't change a full bucket's value
        let trimmed = PiezoSweep.Channel(first: 20, samples: Array(ch.samples.dropFirst(10)))
        #expect(PiezoSweep.bucketAverages(trimmed, firstBucket: 2, count: 1, size: 10)[0] == 24.5)
    }

    @Test("Samples past maxN are ignored")
    func bucketMaxN() {
        let ch = channel(first: 0, count: 20)
        let avgs = PiezoSweep.bucketAverages(ch, firstBucket: 1, count: 1, size: 10, maxN: 12.7)
        #expect(avgs[0] == 11)  // samples 10, 11, 12
    }

    @Test("Robust range ignores a lone spike")
    func robustRangeSpike() throws {
        var samples = (0..<1000).map { Int32($0 % 2 == 0 ? -100 : 100) }
        samples[500] = 1_000_000
        let range = try #require(PiezoSweep.robustRange([PiezoSweep.Channel(first: 0, samples: samples)], fromN: 0))
        #expect(range.hi < 200)
        #expect(range.lo > -200)
    }

    @Test("Robust range only counts samples from fromN")
    func robustRangeWindow() throws {
        let ch = channel(first: 0, count: 100) { $0 < 50 ? 10_000 : 0 }
        let range = try #require(PiezoSweep.robustRange([ch], fromN: 50))
        #expect(range == (-1, 1))
    }

    @Test("Cursor starts at the lag behind the newest sample and advances in real time")
    func cursorAdvance() {
        let start = PiezoSweep.advance(play: nil, first: 0, end: 5000, hz: 500, dt: 0)
        #expect(start == 4250)
        let next = PiezoSweep.advance(play: start, first: 0, end: 5000, hz: 500, dt: 0.1)
        #expect(next == 4300)
    }

    @Test("Cursor never runs past the data and jumps after a long gap")
    func cursorBounds() {
        #expect(PiezoSweep.advance(play: 4990, first: 0, end: 5000, hz: 500, dt: 0.1) == 5000)
        #expect(PiezoSweep.advance(play: 1000, first: 0, end: 10_000, hz: 500, dt: 0.016) == 9250)
    }

    @Test("Range grows fast and shrinks slowly")
    func easing() {
        let grown = PiezoSweep.ease(shown: (-10, 10), target: (-100, 100), dt: 0.12)
        let shrunk = PiezoSweep.ease(shown: (-100, 100), target: (-10, 10), dt: 0.12)
        #expect(grown.hi - 10 > (100 - shrunk.hi) * 5)
    }

    @Test("Drawn samples keep their x as the cursor moves")
    func samplesStayPut() throws {
        let g = PiezoSweep.geometry(hz: 500)
        let ch = channel(first: 0, count: 6000) { Int32($0 % 97) }
        let before = PiezoSweep.runs(ch, play: 5000, geometry: g, width: 400, yOf: { $0 })
        let after = PiezoSweep.runs(ch, play: 5100, geometry: g, width: 400, yOf: { $0 })
        // Bucket 3 of this pass is full in both frames and sits at the same place
        let a = try #require(before.first?[3])
        let b = try #require(after.first?[3])
        #expect(a == b)
    }

    @Test("A gap separates the cursor from the previous sweep")
    func gapAheadOfCursor() {
        let g = PiezoSweep.geometry(hz: 500)
        let ch = channel(first: 0, count: 6000)
        let play = 5000.0  // pass starts at sample 4000, cursor at bucket 50
        let runs = PiezoSweep.runs(ch, play: play, geometry: g, width: 400, yOf: { $0 })
        #expect(runs.count == 2)
        let head = PiezoSweep.cursorX(play: play, geometry: g, width: 400)
        #expect(runs[0].last.map { Double($0.x) } == head)
        let slot = 400.0 / 200
        #expect(Double(runs[1].first!.x) >= head + Double(g.gap) * slot)
    }
}
