import Testing
import Foundation
@testable import Sleepypod

@Suite("Sleep Analyzer")
struct SleepAnalyzerTests {

    @Test("Filters outlier heart rates")
    @MainActor
    func filtersOutliers() {
        let analyzer = SleepAnalyzer()
        let vitals = [
            makeVital(hr: 65, hrv: 40),     // normal
            makeVital(hr: 250, hrv: 50),     // outlier HR — filtered (>130 for sleep)
            makeVital(hr: 60, hrv: 45),      // normal
            makeVital(hr: 70, hrv: 45),      // normal
            makeVital(hr: 62, hrv: 42),      // normal
            makeVital(hr: 68, hrv: 48),      // normal (need 5+ for analyze)
        ]
        analyzer.analyze(vitals: vitals)
        // HR=250 should be filtered, leaving 5 valid records
        #expect(analyzer.stages.count == 5)
    }

    @Test("Quality score penalizes insufficient deep sleep")
    @MainActor
    func qualityScore() {
        let analyzer = SleepAnalyzer()
        // All high HR = light/wake = bad score
        let vitals = (0..<20).map { _ in makeVital(hr: 85, hrv: 20) }
        analyzer.analyze(vitals: vitals)
        #expect(analyzer.qualityScore != nil)
        #expect(analyzer.qualityScore! < 80) // Poor distribution
    }

    @Test("Empty vitals produces no stages")
    @MainActor
    func emptyInput() {
        let analyzer = SleepAnalyzer()
        analyzer.analyze(vitals: [])
        #expect(analyzer.stages.isEmpty)
        #expect(analyzer.qualityScore == nil)
    }

    @Test("Default classification is Light, not REM")
    @MainActor
    func defaultIsLight() {
        let analyzer = SleepAnalyzer()
        // HR near average with normal HRV — should be Light, not REM
        let vitals = (0..<10).map { _ in makeVital(hr: 65, hrv: 35) }
        analyzer.analyze(vitals: vitals)
        let remCount = analyzer.stages.filter { $0.stage == .rem }.count
        let lightCount = analyzer.stages.filter { $0.stage == .light }.count
        // Most epochs should be Light, not REM
        #expect(lightCount > remCount)
    }

    @Test("REM requires positive evidence (low HRV + low movement)")
    @MainActor
    func remRequiresEvidence() {
        let analyzer = SleepAnalyzer()
        // HR slightly above average but HRV is high (>25) — should NOT be REM
        let vitals = (0..<10).map { _ in makeVital(hr: 70, hrv: 40) }
        analyzer.analyze(vitals: vitals)
        let remCount = analyzer.stages.filter { $0.stage == .rem }.count
        #expect(remCount == 0)
    }

    @Test("Deep sleep uses relaxed threshold (hrRatio < 0.92)")
    @MainActor
    func deepSleepThreshold() {
        let analyzer = SleepAnalyzer()
        // Average HR ~65, so HR=58 gives hrRatio ~0.89 < 0.92 → deep
        let vitals = [
            makeVital(hr: 65, hrv: 40),
            makeVital(hr: 65, hrv: 40),
            makeVital(hr: 65, hrv: 40),
            makeVital(hr: 58, hrv: 50),  // should be deep
            makeVital(hr: 58, hrv: 50),  // should be deep
            makeVital(hr: 65, hrv: 40),
        ]
        analyzer.analyze(vitals: vitals)
        let deepCount = analyzer.stages.filter { $0.stage == .deep }.count
        #expect(deepCount >= 2)
    }

    @Test("Low calibration quality caps score at 50")
    @MainActor
    func lowCalibrationCapsScore() {
        let analyzer = SleepAnalyzer()
        let vitals = (0..<20).map { _ in makeVital(hr: 65, hrv: 40) }
        analyzer.analyze(vitals: vitals, calibrationQuality: 0.2)
        #expect(analyzer.qualityScore != nil)
        #expect(analyzer.qualityScore! <= 50)
    }

    @Test("Low calibration quality uses movement-only mode")
    @MainActor
    func lowCalibrationMovementOnly() {
        let analyzer = SleepAnalyzer()
        let vitals = (0..<10).map { _ in makeVital(hr: 65, hrv: 40) }
        // No movement data + low calibration → all Light (movement-only fallback)
        analyzer.analyze(vitals: vitals, calibrationQuality: 0.1)
        let deepCount = analyzer.stages.filter { $0.stage == .deep }.count
        let remCount = analyzer.stages.filter { $0.stage == .rem }.count
        // No Deep or REM when calibration is bad and no movement data
        #expect(deepCount == 0)
        #expect(remCount == 0)
    }

    @Test("BR outliers are filtered")
    @MainActor
    func brOutlierFiltering() {
        let analyzer = SleepAnalyzer()
        let vitals = [
            makeVital(hr: 65, hrv: 40, br: 14),    // normal
            makeVital(hr: 60, hrv: 45, br: 6.8),   // BR too low — filtered
            makeVital(hr: 62, hrv: 42, br: 15),     // normal
            makeVital(hr: 68, hrv: 48, br: 26.6),   // BR too high — filtered
            makeVital(hr: 63, hrv: 43, br: 16),     // normal
            makeVital(hr: 66, hrv: 44, br: 13),     // normal
            makeVital(hr: 64, hrv: 41, br: 15),     // normal
        ]
        analyzer.analyze(vitals: vitals)
        // BR outliers should be filtered, leaving 5 valid records
        #expect(analyzer.stages.count == 5)
    }

    private func makeVital(hr: Double, hrv: Double, br: Double = 14) -> VitalsRecord {
        // Use custom init via JSON decode
        let json = """
        {"id":\(Int.random(in: 1...99999)),"side":"left","timestamp":\(Int(Date().timeIntervalSince1970)),"heartRate":\(hr),"hrv":\(hrv),"breathingRate":\(br)}
        """
        return try! JSONDecoder().decode(VitalsRecord.self, from: json.data(using: .utf8)!)
    }
}
