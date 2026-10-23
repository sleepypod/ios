import Foundation

// Pure snore-capture logic: no audio, no I/O. The audio engine feeds it classifier windows and knock
// onsets; the service turns its output into a session document. Raw audio never reaches this file.

/// One sound-classifier window: where it starts (Unix ms), how long it covers and its snoring confidence.
struct SnoreWindow: Sendable, Equatable {
    let startMs: Int64
    let durationMs: Int64
    let confidence: Double
}

/// A detected snore. Field names follow the training repository's capture contract.
struct SnoreEvent: Codable, Sendable, Equatable {
    var captureId: String
    var startMs: Int64
    var endMs: Int64
    var eventType = "snore"
    var confidence: Double
    var detectorVersion: String
    var labelOrigin = "predicted"
}

/// A half-open span of Unix milliseconds.
struct TimeInterval64: Codable, Sendable, Equatable {
    var startMs: Int64
    var endMs: Int64
    var durationMs: Int64 { endMs - startMs }
}

/// Turns per-window snoring confidence into events with hysteresis: an event opens at `onThreshold`,
/// stays open while windows stay at or above `offThreshold`, and closes after `closeAfterQuietWindows`
/// quieter windows. Events separated by less than `mergeGapMs` join. Confidence is the event's peak.
/// Confidence is the classifier's score, not a calibrated probability.
struct SnoreEventTracker: Sendable {
    var onThreshold = 0.6
    var offThreshold = 0.4
    var closeAfterQuietWindows = 2
    var mergeGapMs: Int64 = 3_000
    let captureId: String
    let detectorVersion: String
    private(set) var events: [SnoreEvent] = []
    private var open: (startMs: Int64, endMs: Int64, peak: Double)?
    private var quiet = 0

    init(captureId: String, detectorVersion: String) {
        self.captureId = captureId
        self.detectorVersion = detectorVersion
    }

    var isOpen: Bool { open != nil }

    mutating func add(_ window: SnoreWindow) {
        let windowEnd = window.startMs + window.durationMs
        if var current = open {
            if window.confidence >= offThreshold {
                current.endMs = max(current.endMs, windowEnd)
                current.peak = max(current.peak, window.confidence)
                quiet = 0
                open = current
            } else {
                quiet += 1
                if quiet >= closeAfterQuietWindows { close() }
            }
            return
        }
        guard window.confidence >= onThreshold else { return }
        if let last = events.last, window.startMs - last.endMs <= mergeGapMs {
            events.removeLast()
            open = (last.startMs, max(last.endMs, windowEnd), max(last.confidence, window.confidence))
        } else {
            open = (window.startMs, windowEnd, window.confidence)
        }
        quiet = 0
    }

    /// Closes any open event, for example when recording stops or is interrupted.
    mutating func finish() { close() }

    private mutating func close() {
        guard let current = open else { return }
        events.append(SnoreEvent(captureId: captureId, startMs: current.startMs, endMs: current.endMs,
                                 confidence: current.peak, detectorVersion: detectorVersion))
        open = nil
        quiet = 0
    }
}

/// The spans the microphone was actually listening. "No snore" only means something inside them.
struct CoverageTracker: Sendable, Equatable {
    private(set) var intervals: [TimeInterval64] = []
    private(set) var openStartMs: Int64?

    mutating func begin(at ms: Int64) {
        guard openStartMs == nil else { return }
        openStartMs = ms
    }

    mutating func end(at ms: Int64) {
        guard let start = openStartMs else { return }
        openStartMs = nil
        if ms > start { intervals.append(TimeInterval64(startMs: start, endMs: ms)) }
    }

    /// Covered milliseconds, counting an open span up to `now`.
    func totalMs(now: Int64? = nil) -> Int64 {
        let closed = intervals.reduce(0) { $0 + $1.durationMs }
        guard let start = openStartMs, let now, now > start else { return closed }
        return closed + now - start
    }
}

/// Finds sharp transients (bed-frame knocks) in microphone samples, in memory only. It keeps an
/// adaptive floor of 5 ms block peaks and reports an onset when a block jumps far above it.
struct KnockDetector: Sendable {
    var ratio: Float = 8
    var minimumPeak: Float = 0.05
    var refractoryMs: Int64 = 150
    private var floor: Float = 0
    private var lastOnsetMs: Int64 = .min / 2
    private var blocksSeen = 0

    /// Returns knock onset times (Unix ms) found in `samples`, which start at `startMs`.
    mutating func process(_ samples: [Float], startMs: Int64, sampleRate: Double) -> [Int64] {
        let block = max(1, Int(sampleRate * 0.005))
        var onsets: [Int64] = []
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + block)
            var peak: Float = 0
            for i in index..<end { peak = max(peak, abs(samples[i])) }
            let ms = startMs + Int64(Double(index) / sampleRate * 1000)
            // Wait for about a quarter second of history before trusting the floor.
            if blocksSeen > 50, peak > minimumPeak, peak > ratio * floor, ms - lastOnsetMs >= refractoryMs {
                onsets.append(ms)
                lastOnsetMs = ms
            }
            floor = blocksSeen == 0 ? peak : floor * 0.995 + peak * 0.005
            blocksSeen += 1
            index = end
        }
        return onsets
    }
}

/// Keeps only the knock onsets the clock sync needs: those in the first and last `windowMs` of a session.
struct KnockWindow: Sendable, Equatable {
    var windowMs: Int64 = 60_000
    let sessionStartMs: Int64
    private(set) var opening: [Int64] = []
    private(set) var recent: [Int64] = []

    init(sessionStartMs: Int64, windowMs: Int64 = 60_000) {
        self.sessionStartMs = sessionStartMs
        self.windowMs = windowMs
    }

    mutating func add(_ onsetMs: Int64) {
        if onsetMs - sessionStartMs <= windowMs { opening.append(onsetMs) }
        recent.append(onsetMs)
        recent.removeAll { onsetMs - $0 > windowMs }
    }

    /// Opening knocks plus those within `windowMs` before the end, without duplicates, in order.
    func knocks(endMs: Int64) -> [Int64] {
        let closing = recent.filter { endMs - $0 <= windowMs && $0 <= endMs }
        return Array(Set(opening + closing)).sorted()
    }
}

/// Why listening paused.
struct CaptureInterruption: Codable, Sendable, Equatable {
    var startMs: Int64
    var endMs: Int64?
    var reason: String
}

/// The capture lifecycle. Coverage and interruptions are kept in step with every transition.
struct CaptureMachine: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case idle, recording, interrupted(String), stopped, failed(String)
    }
    private(set) var state: State = .idle
    private(set) var coverage = CoverageTracker()
    private(set) var interruptions: [CaptureInterruption] = []

    var isActive: Bool {
        switch state {
        case .recording, .interrupted: true
        default: false
        }
    }

    @discardableResult
    mutating func start(at ms: Int64) -> Bool {
        guard !isActive else { return false }
        state = .recording
        coverage = CoverageTracker()
        interruptions = []
        coverage.begin(at: ms)
        return true
    }

    @discardableResult
    mutating func interrupt(_ reason: String, at ms: Int64) -> Bool {
        guard state == .recording else { return false }
        coverage.end(at: ms)
        interruptions.append(CaptureInterruption(startMs: ms, endMs: nil, reason: reason))
        state = .interrupted(reason)
        return true
    }

    @discardableResult
    mutating func resume(at ms: Int64) -> Bool {
        guard case .interrupted = state else { return false }
        closeInterruption(at: ms)
        coverage.begin(at: ms)
        state = .recording
        return true
    }

    @discardableResult
    mutating func stop(at ms: Int64) -> Bool {
        guard isActive else { return false }
        coverage.end(at: ms)
        closeInterruption(at: ms)
        state = .stopped
        return true
    }

    mutating func fail(_ reason: String, at ms: Int64) {
        coverage.end(at: ms)
        closeInterruption(at: ms)
        state = .failed(reason)
    }

    private mutating func closeInterruption(at ms: Int64) {
        if let last = interruptions.indices.last, interruptions[last].endMs == nil {
            interruptions[last].endMs = ms
        }
    }
}

/// Maps audio host time (seconds) to Unix milliseconds from one anchor taken when capture starts.
struct HostClockAnchor: Sendable, Equatable {
    let unixMs: Int64
    let hostSeconds: Double

    func unixMs(hostSeconds seconds: Double) -> Int64 {
        unixMs + Int64(((seconds - hostSeconds) * 1000).rounded())
    }
}

/// What the session file holds. Only times, confidences and coverage: never audio.
struct SnoreSessionDocument: Codable, Sendable, Equatable {
    static let currentSchema = "sleepypod-snore-capture-v1"

    struct Classifier: Codable, Sendable, Equatable {
        var identifier = "SNClassifierIdentifier.version1"
        var label = "snoring"
        var windowSeconds: Double
        var overlapFactor: Double
        var onThreshold: Double
        var offThreshold: Double
    }

    var schemaVersion = Self.currentSchema
    var captureId: String
    var source = "iphone-microphone"
    var device: String
    var osVersion: String
    var appVersion: String
    var timeZone: String
    var units = "unix-ms"
    var startMs: Int64
    var endMs: Int64?
    var sampleRate: Double?
    var channelCount: Int?
    var detectorVersion: String
    var classifier: Classifier
    var coverage: [TimeInterval64] = []
    var interruptions: [CaptureInterruption] = []
    var events: [SnoreEvent] = []
    var knocks: [Int64] = []
    var stopReason: String?

    var coveredMs: Int64 { coverage.reduce(0) { $0 + $1.durationMs } }
    var snoreMs: Int64 { events.reduce(0) { $0 + ($1.endMs - $1.startMs) } }
    var longestEventMs: Int64 { events.map { $0.endMs - $0.startMs }.max() ?? 0 }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
