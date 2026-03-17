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

        // Autocorrelation via vDSP
        var acf = [Float](repeating: 0, count: n)
        vDSP_conv(signal, 1, signal, 1, &acf, 1, vDSP_Length(n), vDSP_Length(n))

        // Normalize by zero-lag value
        guard let zeroLag = acf.first, zeroLag > 0 else {
            return (nil, 0)
        }
        vDSP.divide(acf, zeroLag, result: &acf)

        // Search range in samples
        let minLag = max(1, Int(Double(sampleRate) / maxFreq))
        let maxLag = min(n - 1, Int(Double(sampleRate) / minFreq))
        guard minLag < maxLag else { return (nil, 0) }

        // Find peak in valid range
        let searchRange = Array(acf[minLag...maxLag])
        guard let peakVal = searchRange.max(),
              let peakIdx = searchRange.firstIndex(of: peakVal) else {
            return (nil, 0)
        }

        let lag = minLag + peakIdx
        let frequency = Double(sampleRate) / Double(lag)
        let confidence = Double(peakVal)

        guard confidence > 0.15 else { return (nil, confidence) }
        return (frequency, confidence)
    }
}
