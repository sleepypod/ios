import Testing
import Foundation
@testable import Sleepypod

private final class FixtureAnchor {}

/// The feature-contract half of the parity check: one real night's raw vitals and movement, with the rows the
/// Python port in sleepypod-core (`docs/research/sleep-stage-calibration/personal-models.py --fixture`) computes
/// from them. The Swift feature type must reproduce every column, or the container's models and the phone's
/// disagree about what they are looking at.
@Suite("Stage feature parity with the analysis container")
struct StageFeatureParityTests {
    private struct Fixture: Decodable {
        struct Vital: Decodable { let ts: Int; let hr: Double?; let hrv: Double?; let br: Double? }
        struct Movement: Decodable { let ts: Int; let total: Double }
        let enteredBed: Int
        let leftBed: Int
        let vitals: [Vital]
        let movement: [Movement]
        let contractA: [[String: Double]]
        let contractB: [[String: Double]]
        let contractC: [[String: Double]]
    }

    private func load() throws -> Fixture {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: "stage-features-night", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func compare(_ rows: [StageChallenger.FeatureEpoch], to expected: [[String: Double]], columns: [String]) {
        #expect(rows.count == expected.count)
        for (row, want) in zip(rows, expected) {
            #expect(row.start.timeIntervalSince1970 == want["start"])
            for column in columns {
                let got = row.values[column]
                #expect(got != nil, Comment(rawValue: column))
                if let got, let wanted = want[column] {
                    #expect(abs(got - wanted) < 1e-6, "\(column) at \(row.start): swift \(got), python \(wanted)")
                }
            }
        }
    }

    @Test func swiftFeaturesMatchThePythonPortOnARealNight() throws {
        let fixture = try load()
        let allVitals = fixture.vitals.enumerated().map { index, v in
            VitalsRecord(id: index, heartRate: v.hr, hrv: v.hrv, breathingRate: v.br, date: Date(timeIntervalSince1970: Double(v.ts)))
        }
        let allMovement = fixture.movement.enumerated().map { index, m in
            MovementRecord(id: index, totalMovement: Int(m.total), date: Date(timeIntervalSince1970: Double(m.ts)))
        }
        let enteredBed = Date(timeIntervalSince1970: Double(fixture.enteredBed))
        let leftBed = Date(timeIntervalSince1970: Double(fixture.leftBed))
        // The app hands the feature code only the record window's rows; the fixture carries the padding too.
        let vitals = allVitals.filter { $0.date >= enteredBed && $0.date < leftBed }
        let movement = allMovement.filter { $0.date >= enteredBed && $0.date < leftBed }
        #expect(!fixture.contractA.isEmpty)
        compare(StageFeatures.rows(contract: .challenger, enteredBed: enteredBed, leftBed: leftBed, vitals: vitals, movement: movement),
                to: fixture.contractA, columns: StageFeatures.Contract.challenger.columns)
        compare(StageFeatures.rows(contract: .podNative, enteredBed: enteredBed, leftBed: leftBed, vitals: vitals, movement: movement),
                to: fixture.contractB, columns: StageFeatures.Contract.podNative.columns)
        // podContext rows come from core's own `stageModelFeatures` (personal-stage-model.ts), which stages the pod's nights.
        #expect(!fixture.contractC.isEmpty)
        compare(StageFeatures.rows(contract: .podContext, enteredBed: enteredBed, leftBed: leftBed, vitals: vitals, movement: movement),
                to: fixture.contractC, columns: StageFeatures.Contract.podContext.columns)
    }
}
