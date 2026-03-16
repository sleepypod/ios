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
            makeVital(hr: 250, hrv: 50),     // outlier HR — filtered
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

    private func makeVital(hr: Double, hrv: Double) -> VitalsRecord {
        // Use custom init via JSON decode
        let json = """
        {"id":\(Int.random(in: 1...9999)),"side":"left","timestamp":\(Int(Date().timeIntervalSince1970)),"heartRate":\(hr),"hrv":\(hrv),"breathingRate":14}
        """
        return try! JSONDecoder().decode(VitalsRecord.self, from: json.data(using: .utf8)!)
    }
}
