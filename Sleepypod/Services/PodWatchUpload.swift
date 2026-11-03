import Foundation

/// Apple Watch readings sent from this iPhone into the pod's reference tables: the same rows
/// sleepypod-core's scripts/import-watch-health.py writes from a Health export, so the pod can score its
/// own staging and vitals against the Watch. Pure value work, so it runs without a Health store in tests.
enum PodWatchUpload {
    struct Segment: Sendable, Equatable {
        let start: Int
        let end: Int
        let stage: SleepAnalyzer.SleepStage
    }
    struct Sample: Sendable, Equatable {
        let timestamp: Int
        let value: Double
    }
    enum Metric: String, Sendable {
        case breathingRate = "breathing_rate"
        case hrvSDNN = "hrv_sdnn"

        /// The pod rejects a whole batch holding a value outside these (REFERENCE_SAMPLE_RANGE in core).
        var range: ClosedRange<Double> {
            switch self {
            case .breathingRate: 4...60
            case .hrvSDNN: 1...500
            }
        }
    }
    struct Report: Sendable, Equatable {
        var stages = 0, heartRate = 0, breathing = 0, hrv = 0
        var matchedStages = 0, matchedHeartRate = 0, matchedBreathing = 0, matchedHRV = 0
        /// Nights the pod refused because they overlap stored segments with different boundaries.
        var rejectedNights = 0
        var written: Int { stages + heartRate + breathing + hrv }
    }

    /// The API caps every import at 2000 items per call.
    static let batchSize = 2000
    static let heartRateRange: ClosedRange<Double> = 20...250

    /// The pod's refusal of a night it already holds with other boundaries (importReferenceStages BAD_REQUEST).
    static func isBoundaryConflict(_ message: String) -> Bool {
        message.contains("overlap stored reference stages")
    }

    static func podStage(_ stage: SleepAnalyzer.SleepStage) -> String {
        switch stage {
        case .wake: "wake"
        case .light: "light"
        case .deep: "deep"
        case .rem: "rem"
        }
    }

    /// Whole Unix seconds, non-overlapping and sorted. Overlaps resolve as the importer does (the segment
    /// starting latest wins) and runs of one stage merge, so a night posted from here matches the same night
    /// imported from an export and re-posting it is a no-op.
    static func segments(_ samples: [WatchComparison.StageSample]) -> [Segment] {
        func seconds(_ date: Date) -> Int { Int(date.timeIntervalSince1970.rounded(.down)) }
        let floored: [Segment] = samples.map { Segment(start: seconds($0.start), end: seconds($0.end), stage: $0.stage) }
            .filter { $0.end > $0.start }
            .sorted { a, b in
                if a.start != b.start { return a.start < b.start }
                if a.end != b.end { return a.end < b.end }
                return podStage(a.stage) < podStage(b.stage)
            }
        let bounds: [Int] = Set(floored.flatMap { [$0.start, $0.end] }).sorted()
        var result: [Segment] = []
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            guard let stage = floored.last(where: { $0.start <= a && $0.end > a })?.stage else { continue }
            if let last = result.last, last.end == a, last.stage == stage {
                result[result.count - 1] = Segment(start: last.start, end: b, stage: stage)
            } else {
                result.append(Segment(start: a, end: b, stage: stage))
            }
        }
        return result
    }

    /// One post per night, so a night the pod already holds with other boundaries blocks only itself.
    static func nights(_ segments: [Segment], maxGap: Int = 3 * 3600) -> [[Segment]] {
        var nights: [[Segment]] = []
        for segment in segments {
            if let last = nights.last?.last, segment.start - last.end <= maxGap {
                nights[nights.count - 1].append(segment)
            } else {
                nights.append([segment])
            }
        }
        return nights.flatMap { chunks($0) }
    }

    static func samples(_ readings: [WatchComparison.Reading], in range: ClosedRange<Double>) -> [Sample] {
        readings.filter { $0.value.isFinite && range.contains($0.value) }
            .map { Sample(timestamp: Int($0.date.timeIntervalSince1970.rounded(.down)), value: $0.value) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    static func chunks<T>(_ items: [T], size: Int = batchSize) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }
}

/// A night of Watch wrist movement set against the pod's movement score for the same side. The two measure
/// different things (wrist jerk against bed capacitance per minute), so each is scaled to its own range for
/// drawing and they are compared by correlation, not by value.
struct WatchMotionComparison: Sendable {
    struct Point: Sendable, Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    /// Watch moving readings per minute, by Unix minute.
    let watch: [Point]
    let pod: [Point]
    /// Pod minutes paired with the Watch bins inside the same 60 s window.
    let pairs: [(pod: Double, watch: Double)]

    var correlation: Double? { Self.pearson(pairs) }
    var watchPeak: Double { Self.peak(watch.map(\.value)) }
    var podPeak: Double { Self.peak(pod.map(\.value)) }

    static func build(file: WatchMotionFile, pod records: [MovementRecord]) -> WatchMotionComparison {
        let bins = file.bins
        var perMinute: [Int64: Double] = [:]
        for index in 0..<bins.count {
            perMinute[bins.startMs[index] / 60_000, default: 0] += Double(bins.movingSamples[index])
        }
        var watch: [Point] = perMinute.sorted { $0.key < $1.key }
            .map { minute, moving in Point(date: Date(timeIntervalSince1970: Double(minute) * 60), value: moving) }
        let from = Date(timeIntervalSince1970: Double(file.recordedFromMs) / 1000)
        let to = Date(timeIntervalSince1970: Double(file.recordedToMs) / 1000)
        var pod = records.filter { $0.date >= from && $0.date <= to.addingTimeInterval(60) }
            .sorted { $0.date < $1.date }
            .map { Point(date: $0.date, value: Double($0.totalMovement)) }

        // Keep only the span both sensors cover, so a Watch taken off early or a pod that started late leaves
        // no stretch of one sensor with nothing to compare against. A Watch minute starts at its date; a pod
        // minute ends at it.
        if let watchFirst = watch.first?.date, let watchLast = watch.last?.date,
           let podFirst = pod.first?.date, let podLast = pod.last?.date {
            let start = max(watchFirst, podFirst.addingTimeInterval(-60))
            let end = min(watchLast.addingTimeInterval(60), podLast)
            if start < end {
                watch = watch.filter { $0.date.addingTimeInterval(60) > start && $0.date < end }
                pod = pod.filter { $0.date > start && $0.date.addingTimeInterval(-60) < end }
            }
        }

        // Each pod reading summarises the minute before its timestamp.
        let order = bins.startMs.indices.sorted { bins.startMs[$0] < bins.startMs[$1] }
        let starts = order.map { bins.startMs[$0] }
        var pairs: [(pod: Double, watch: Double)] = []
        for point in pod {
            let end = Int64((point.date.timeIntervalSince1970 * 1000).rounded())
            let lo = lowerBound(starts, end - 60_000), hi = lowerBound(starts, end)
            guard hi > lo else { continue }
            pairs.append((point.value, order[lo..<hi].reduce(0) { $0 + Double(bins.movingSamples[$1]) }))
        }
        return WatchMotionComparison(watch: watch, pod: pod, pairs: pairs)
    }

    private static func lowerBound(_ sorted: [Int64], _ value: Int64) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The 95th percentile, so one thrash does not flatten the rest of the night.
    static func peak(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 1 }
        return max(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], 1)
    }

    static func pearson(_ pairs: [(pod: Double, watch: Double)]) -> Double? {
        guard pairs.count >= 10 else { return nil }
        let n = Double(pairs.count)
        let mx = pairs.map(\.pod).reduce(0, +) / n, my = pairs.map(\.watch).reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for pair in pairs {
            sxy += (pair.pod - mx) * (pair.watch - my)
            sxx += (pair.pod - mx) * (pair.pod - mx)
            syy += (pair.watch - my) * (pair.watch - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }
}
