import Foundation

/// One accelerometer reading from the Watch: Unix seconds and acceleration in g, gravity included.
struct MotionSample: Sendable, Equatable {
    var time: Double
    var x: Double
    var y: Double
    var z: Double

    var magnitude: Double { (x * x + y * y + z * z).squareRoot() }
}

/// Fixed-width summaries of a night's wrist acceleration, small enough to send to the iPhone and used by
/// sleepypod/training as movement labels. Format documented in docs/watch-motion-format.md.
struct WatchMotionFile: Codable, Sendable, Equatable {
    static let currentVersion = "watch-motion-v1"

    var version = WatchMotionFile.currentVersion
    var recordedFromMs: Int64
    var recordedToMs: Int64
    var timeZone: String
    var utcOffsetSeconds: Int
    var sampleRateHz: Double
    var binSeconds: Double
    var jerkThresholdGPerSecond: Double
    var device: String
    var bins: Bins
    /// Raw readings as [Unix ms, x, y, z]; nil unless raw export was requested.
    var raw: [[Double]]?

    /// Columnar so a night of 2 s bins stays a few hundred kilobytes of JSON.
    struct Bins: Codable, Sendable, Equatable {
        var startMs: [Int64] = []
        var samples: [Int] = []
        var meanMagnitude: [Double] = []
        var magnitudeVariance: [Double] = []
        var maxJerk: [Double] = []
        var movingSamples: [Int] = []

        var count: Int { startMs.count }
    }

    enum FormatError: Error, Equatable {
        case unsupportedVersion(String)
        case mismatchedColumns
        case badInterval
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> WatchMotionFile {
        let file = try JSONDecoder().decode(WatchMotionFile.self, from: data)
        try file.validate()
        return file
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw FormatError.unsupportedVersion(version) }
        guard recordedToMs >= recordedFromMs, binSeconds > 0 else { throw FormatError.badInterval }
        let n = bins.count
        guard [bins.samples.count, bins.meanMagnitude.count, bins.magnitudeVariance.count,
               bins.maxJerk.count, bins.movingSamples.count].allSatisfy({ $0 == n }) else {
            throw FormatError.mismatchedColumns
        }
    }

    /// `watch-motion-<start Unix ms>.json`, so files sort by night and never collide.
    var fileName: String { "watch-motion-\(recordedFromMs).json" }
}

enum MotionSummarizer {
    static let defaultBinSeconds = 2.0
    /// Rate of change of |a| above which a reading counts as moving. Wrist tremor and breathing stay well below it.
    static let defaultJerkThreshold = 1.0

    /// Bins aligned to Unix time, so bins from different nights and devices line up. Bins with no readings are
    /// omitted: a missing bin means no data, never stillness. Jerk is measured only between consecutive readings
    /// inside one bin and at most `maxGap` apart.
    static func summarize(_ samples: [MotionSample], binSeconds: Double = defaultBinSeconds,
                          jerkThreshold: Double = defaultJerkThreshold, maxGap: Double = 0.5) -> WatchMotionFile.Bins {
        var bins = WatchMotionFile.Bins()
        let sorted = samples.sorted { $0.time < $1.time }
        var index = 0
        while index < sorted.count {
            let binStart = (sorted[index].time / binSeconds).rounded(.down) * binSeconds
            let binEnd = binStart + binSeconds
            var magnitudes: [Double] = []
            var maxJerk = 0.0
            var moving = 0
            var previous: MotionSample?
            while index < sorted.count, sorted[index].time < binEnd {
                let sample = sorted[index]
                if let previous, sample.time > previous.time, sample.time - previous.time <= maxGap {
                    let jerk = abs(sample.magnitude - previous.magnitude) / (sample.time - previous.time)
                    maxJerk = max(maxJerk, jerk)
                    if jerk > jerkThreshold { moving += 1 }
                }
                magnitudes.append(sample.magnitude)
                previous = sample
                index += 1
            }
            let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
            let variance = magnitudes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(magnitudes.count)
            bins.startMs.append(Int64((binStart * 1000).rounded()))
            bins.samples.append(magnitudes.count)
            bins.meanMagnitude.append(mean)
            bins.magnitudeVariance.append(variance)
            bins.maxJerk.append(maxJerk)
            bins.movingSamples.append(moving)
        }
        return bins
    }

    static func file(samples: [MotionSample], from: Date, to: Date, timeZone: TimeZone, device: String,
                     sampleRateHz: Double = 50, binSeconds: Double = defaultBinSeconds,
                     jerkThreshold: Double = defaultJerkThreshold, includeRaw: Bool = false) -> WatchMotionFile {
        WatchMotionFile(
            recordedFromMs: Int64((from.timeIntervalSince1970 * 1000).rounded()),
            recordedToMs: Int64((to.timeIntervalSince1970 * 1000).rounded()),
            timeZone: timeZone.identifier,
            utcOffsetSeconds: timeZone.secondsFromGMT(for: from),
            sampleRateHz: sampleRateHz, binSeconds: binSeconds, jerkThresholdGPerSecond: jerkThreshold,
            device: device,
            bins: summarize(samples, binSeconds: binSeconds, jerkThreshold: jerkThreshold),
            raw: includeRaw ? samples.map { [($0.time * 1000).rounded(), $0.x, $0.y, $0.z] } : nil)
    }
}

/// When and how long to ask the Watch to record. Apple's recorder takes at most 12 hours per request.
struct RecordingPlan: Codable, Sendable, Equatable {
    static let maximumDuration: TimeInterval = 12 * 3600

    var start: Date
    var duration: TimeInterval

    init(start: Date, hours: Double) {
        self.start = start
        duration = min(max(hours, 0.5) * 3600, Self.maximumDuration)
    }

    var end: Date { start.addingTimeInterval(duration) }

    /// The span that can be read back now: from the start until now or the planned end, whichever is first.
    func readableInterval(now: Date) -> DateInterval? {
        let stop = min(now, end)
        return stop > start ? DateInterval(start: start, end: stop) : nil
    }
}
