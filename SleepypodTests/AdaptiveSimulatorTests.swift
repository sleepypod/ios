import Foundation
import Testing
@testable import Sleepypod

@Suite("Adaptive Simulator")
struct AdaptiveSimulatorTests {

    // MARK: - Helpers

    private func makeVitals(count: Int, baseHR: Double = 65, hrv: Double? = 40, startDate: Date = Date()) -> [VitalsRecord] {
        (0..<count).map { i in
            let date = startDate.addingTimeInterval(Double(i) * 60)
            return VitalsRecord(
                id: i,
                side: "left",
                heartRate: baseHR + Double.random(in: -3...3),
                hrv: hrv,
                breathingRate: 14,
                date: date
            )
        }
    }

    private func makeMovement(count: Int, baseMovement: Int = 50, startDate: Date = Date()) -> [MovementRecord] {
        (0..<count).map { i in
            MovementRecord(
                id: i,
                side: "left",
                totalMovement: baseMovement + Int.random(in: -20...20),
                date: startDate.addingTimeInterval(Double(i) * 60)
            )
        }
    }

    // MARK: - Tests

    @Test("Stable night produces minimal recommendations")
    func stableNight() {
        let start = Date()
        let vitals = makeVitals(count: 60, baseHR: 65, startDate: start)
        let movement = makeMovement(count: 60, baseMovement: 30, startDate: start)

        let recs = AdaptiveSimulator.simulate(vitals: vitals, movement: movement)
        // Stable vitals shouldn't produce many changes
        #expect(recs.count <= 5)
    }

    @Test("Low HR triggers cooling recommendation")
    func deepSleepCooling() {
        let start = Date()
        // Normal HR for first 10 min, then drop to deep sleep levels
        var vitals = makeVitals(count: 10, baseHR: 65, startDate: start)
        vitals += makeVitals(count: 30, baseHR: 55, startDate: start.addingTimeInterval(600))
        let movement = makeMovement(count: 40, baseMovement: 10, startDate: start)

        let config = AdaptiveSimulator.Config(initialTemp: 78, adjustmentIntervalMinutes: 5)
        let recs = AdaptiveSimulator.simulate(vitals: vitals, movement: movement, config: config)

        let coolingRecs = recs.filter { $0.recommendedTemp < $0.currentTemp }
        #expect(!coolingRecs.isEmpty)
        #expect(coolingRecs.allSatisfy { $0.reason.contains("deep_sleep") || $0.reason.contains("cooling") })
    }

    @Test("High movement pauses adjustments")
    func wakeDetection() {
        let start = Date()
        let vitals = makeVitals(count: 30, baseHR: 75, startDate: start)
        let movement = makeMovement(count: 30, baseMovement: 300, startDate: start)

        let recs = AdaptiveSimulator.simulate(vitals: vitals, movement: movement)

        // Wake should pause — no temperature changes during high movement
        let wakeRecs = recs.filter { $0.reason.contains("wake") }
        let activeChanges = recs.filter { $0.recommendedTemp != $0.currentTemp }
        // Most recs during wake should be pauses (no change filtered out), few active changes
        #expect(activeChanges.count <= 2)
    }

    @Test("Poor calibration limits to movement-only decisions")
    func degradedMode() {
        let start = Date()
        let vitals = makeVitals(count: 30, baseHR: 55, hrv: 50, startDate: start)
        let movement = makeMovement(count: 30, baseMovement: 20, startDate: start)

        let config = AdaptiveSimulator.Config(calibrationQuality: 0.1)
        let recs = AdaptiveSimulator.simulate(vitals: vitals, movement: movement, config: config)

        // With poor calibration, shouldn't classify as deep sleep even with low HR
        let deepRecs = recs.filter { $0.sleepStage == .deep }
        #expect(deepRecs.isEmpty)
    }

    @Test("Recommendations respect min/max bounds")
    func boundsRespected() {
        let start = Date()
        let vitals = makeVitals(count: 60, baseHR: 50, startDate: start)
        let movement = makeMovement(count: 60, baseMovement: 5, startDate: start)

        let config = AdaptiveSimulator.Config(initialTemp: 70, minTemp: 65, maxTemp: 85)
        let recs = AdaptiveSimulator.simulate(vitals: vitals, movement: movement, config: config)

        for rec in recs {
            #expect(rec.recommendedTemp >= config.minTemp)
            #expect(rec.recommendedTemp <= config.maxTemp)
        }
    }

    @Test("Confidence reflects calibration quality")
    func confidenceScaling() {
        let start = Date()
        let vitals = makeVitals(count: 30, baseHR: 55, startDate: start)
        let movement = makeMovement(count: 30, baseMovement: 10, startDate: start)

        let highCal = AdaptiveSimulator.Config(calibrationQuality: 1.0)
        let lowCal = AdaptiveSimulator.Config(calibrationQuality: 0.3)

        let highRecs = AdaptiveSimulator.simulate(vitals: vitals, movement: movement, config: highCal)
        let lowRecs = AdaptiveSimulator.simulate(vitals: vitals, movement: movement, config: lowCal)

        let highAvgConf = highRecs.isEmpty ? 0 : highRecs.map(\.confidence).reduce(0, +) / Double(highRecs.count)
        let lowAvgConf = lowRecs.isEmpty ? 0 : lowRecs.map(\.confidence).reduce(0, +) / Double(lowRecs.count)

        if !highRecs.isEmpty && !lowRecs.isEmpty {
            #expect(highAvgConf > lowAvgConf)
        }
    }
}
