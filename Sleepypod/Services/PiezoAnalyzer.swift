import Accelerate
import Foundation

/// Extracts heart rate and breathing rate from raw piezo (BCG) signals
/// using autocorrelation via Accelerate/vDSP.
enum PiezoAnalyzer {

    /// Extract vitals from a single piezo frame.
    /// - Parameters:
    ///   - signal: Raw int32 samples from one side (~500 samples at 500 Hz = 1 second)
    ///   - sampleRate: Samples per second (typically 500)
    static func extractVitals(signal: [Int32], sampleRate: Int = 500) -> LiveVitals {
        guard signal.count >= 200 else { return LiveVitals() }

        // Convert to Float and remove DC offset
        var floats = signal.map { Float($0) }
        let mean = vDSP.mean(floats)
        vDSP.add(-mean, floats, result: &floats)

        // Heart rate: bandpass ~0.8–3.0 Hz (48–180 BPM)
        let hr = extractRate(
            signal: floats,
            sampleRate: sampleRate,
            minFreq: 0.8,
            maxFreq: 3.0
        )

        // Breathing rate: bandpass ~0.1–0.5 Hz (6–30 BPM)
        let br = extractRate(
            signal: floats,
            sampleRate: sampleRate,
            minFreq: 0.1,
            maxFreq: 0.5
        )

        return LiveVitals(
            heartRate: hr.rate.map { $0 * 60 },  // Convert Hz to BPM
            breathingRate: br.rate.map { $0 * 60 },
            confidence: hr.confidence
        )
    }

    private static func extractRate(
        signal: [Float],
        sampleRate: Int,
        minFreq: Double,
        maxFreq: Double
    ) -> (rate: Double?, confidence: Double) {
        let n = signal.count
        guard n > 1 else { return (nil, 0) }

        // Autocorrelation: acf[lag] = sum(signal[i] * signal[i+lag]) for valid i
        let minLag = max(1, Int(Double(sampleRate) / maxFreq))
        let maxLag = min(n - 1, Int(Double(sampleRate) / minFreq))
        guard minLag < maxLag else { return (nil, 0) }

        // Compute zero-lag energy for normalization
        var energy: Float = 0
        vDSP_dotpr(signal, 1, signal, 1, &energy, vDSP_Length(n))
        guard energy > 0 else { return (nil, 0) }

        // Compute autocorrelation only for lags we care about
        var bestLag = minLag
        var bestVal: Float = -.greatestFiniteMagnitude
        for lag in minLag...maxLag {
            var dot: Float = 0
            let len = n - lag
            guard len > 0 else { continue }
            vDSP_dotpr(signal, 1, Array(signal[lag...]), 1, &dot, vDSP_Length(len))
            let normalized = dot / energy
            if normalized > bestVal {
                bestVal = normalized
                bestLag = lag
            }
        }

        let confidence = Double(max(0, bestVal))
        guard confidence > 0.15 else { return (nil, confidence) }

        let frequency = Double(sampleRate) / Double(bestLag)
        return (frequency, confidence)
    }
}
