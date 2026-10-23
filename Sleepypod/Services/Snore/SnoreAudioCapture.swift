@preconcurrency import AVFoundation
import Foundation
@preconcurrency import SoundAnalysis

/// What the audio source reports when it starts.
struct SnoreAudioFormat: Sendable, Equatable {
    var sampleRate: Double
    var channelCount: Int
    var windowSeconds: Double
    var overlapFactor: Double
}

enum SnoreCaptureError: LocalizedError, Equatable {
    case snoringUnavailable
    case noInput
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .snoringUnavailable: "This iOS version's sound classifier has no snoring label, so snore detection can't run."
        case .noInput: "No microphone input is available."
        case .engine(let message): "The microphone couldn't start: \(message)"
        }
    }
}

/// The microphone side of snore capture, behind a protocol so the service can be tested without audio.
protocol SnoreAudioSource: AnyObject, Sendable {
    func start(onWindow: @escaping @Sendable (SnoreWindow) -> Void,
               onKnock: @escaping @Sendable (Int64) -> Void) throws -> SnoreAudioFormat
    func stop()
}

/// Microphone permission, behind a protocol for tests.
protocol MicrophonePermission: Sendable {
    var isGranted: Bool { get }
    var isDenied: Bool { get }
    func request() async -> Bool
}

struct SystemMicrophonePermission: MicrophonePermission {
    var isGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }
    var isDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }
    func request() async -> Bool { await AVAudioApplication.requestRecordPermission() }
}

/// Listens with AVAudioEngine and classifies each buffer with Apple's built-in sound classifier.
/// Buffers live only in memory for the classifier and knock detector; nothing is written or sent.
final class MicrophoneSnoreSource: NSObject, SnoreAudioSource, SNResultsObserving, @unchecked Sendable {
    static let snoringLabel = "snoring"
    private let queue = DispatchQueue(label: "sleepypod.snore.analysis")
    private let engine = AVAudioEngine()
    // Touched only on `queue` after start.
    private var analyzer: SNAudioStreamAnalyzer?
    private var framePosition: AVAudioFramePosition = 0
    private var firstBufferMs: Int64?
    private var anchor: HostClockAnchor?
    private var knockDetector = KnockDetector()
    private var onWindow: (@Sendable (SnoreWindow) -> Void)?
    private var onKnock: (@Sendable (Int64) -> Void)?

    func start(onWindow: @escaping @Sendable (SnoreWindow) -> Void,
               onKnock: @escaping @Sendable (Int64) -> Void) throws -> SnoreAudioFormat {
        let request: SNClassifySoundRequest
        do {
            request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        } catch {
            throw SnoreCaptureError.engine(error.localizedDescription)
        }
        guard request.knownClassifications.contains(Self.snoringLabel) else { throw SnoreCaptureError.snoringUnavailable }
        request.overlapFactor = 0.5

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        } catch {
            throw SnoreCaptureError.engine(error.localizedDescription)
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SnoreCaptureError.noInput }

        let analyzer = SNAudioStreamAnalyzer(format: format)
        do {
            try analyzer.add(request, withObserver: self)
        } catch {
            throw SnoreCaptureError.engine(error.localizedDescription)
        }
        queue.sync {
            self.analyzer = analyzer
            self.framePosition = 0
            self.firstBufferMs = nil
            self.knockDetector = KnockDetector()
            self.anchor = HostClockAnchor(unixMs: Int64(Date().timeIntervalSince1970 * 1000),
                                          hostSeconds: AVAudioTime.seconds(forHostTime: mach_absolute_time()))
            self.onWindow = onWindow
            self.onKnock = onKnock
        }
        input.installTap(onBus: 0, bufferSize: 8_192, format: format) { [weak self] buffer, when in
            guard let self else { return }
            self.queue.async { self.analyze(buffer, at: when) }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SnoreCaptureError.engine(error.localizedDescription)
        }
        return SnoreAudioFormat(sampleRate: format.sampleRate, channelCount: Int(format.channelCount),
                                windowSeconds: request.windowDuration.seconds, overlapFactor: request.overlapFactor)
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        queue.sync {
            analyzer?.completeAnalysis()
            analyzer = nil
            onWindow = nil
            onKnock = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func analyze(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
        guard let analyzer, let anchor else { return }
        let bufferMs = when.isHostTimeValid
            ? anchor.unixMs(hostSeconds: AVAudioTime.seconds(forHostTime: when.hostTime))
            : anchor.unixMs + Int64(Double(framePosition) / buffer.format.sampleRate * 1000)
        if firstBufferMs == nil { firstBufferMs = bufferMs - Int64(Double(framePosition) / buffer.format.sampleRate * 1000) }
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
        if let channel = buffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            for onset in knockDetector.process(samples, startMs: bufferMs, sampleRate: buffer.format.sampleRate) {
                onKnock?(onset)
            }
        }
    }

    // SNResultsObserving: delivered on the analyzer's thread.
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let confidence = result.classification(forIdentifier: Self.snoringLabel)?.confidence ?? 0
        let offsetMs = Int64(result.timeRange.start.seconds * 1000)
        let durationMs = Int64(result.timeRange.duration.seconds * 1000)
        queue.async { [weak self] in
            guard let self, let origin = self.firstBufferMs else { return }
            self.onWindow?(SnoreWindow(startMs: origin + offsetMs, durationMs: durationMs, confidence: confidence))
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        Log.general.error("snore classifier failed: \(error.localizedDescription, privacy: .public)")
    }
}
