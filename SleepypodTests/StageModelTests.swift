import Testing
import Foundation
@testable import Sleepypod

/// A fixed rule from named columns to a class, standing in for a trained model.
private struct RuleClassifier: SleepStageClassifying {
    let rule: @Sendable ([String: Double]) -> Int64
    func predict(_ features: [String: Double]) throws -> StageChallenger.Prediction {
        let label = rule(features)
        return StageChallenger.Prediction(classLabel: label, probabilities: [label: 1])
    }
}

@Suite("Personal stage models")
@MainActor
struct StageModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private typealias Block = WatchComparison.StageSample

    private func vital(_ minute: Int, hr: Double?, hrv: Double? = nil, br: Double? = nil) -> VitalsRecord {
        VitalsRecord(id: minute, heartRate: hr, hrv: hrv, breathingRate: br, date: t0.addingTimeInterval(Double(minute) * 60))
    }
    private func block(_ fromMinute: Double, _ toMinute: Double, _ stage: SleepAnalyzer.SleepStage) -> Block {
        Block(start: t0.addingTimeInterval(fromMinute * 60), end: t0.addingTimeInterval(toMinute * 60), stage: stage)
    }
    private func row(_ minute: Double, _ label: SleepAnalyzer.SleepStage) -> StageDataset.LabeledRow {
        .init(start: t0.addingTimeInterval(minute * 60), values: ["x": minute], label: label)
    }

    // MARK: Features

    @Test func podNativeContractAddsItsColumnsToTheChallengerOnes() throws {
        // 20 minutes in bed, one vital a minute: HR 60 for the first epoch, 70 for the second, HRV 20 then 40.
        let vitals = (0..<20).map { vital($0, hr: $0 < 10 ? 60 : 70, hrv: $0 < 10 ? 20 : 40, br: 14 + Double($0 % 2)) }
        let movement = [MovementRecord(id: 1, totalMovement: 50, date: t0.addingTimeInterval(120))]
        let rows = StageFeatures.rows(contract: .podNative, enteredBed: t0, leftBed: t0.addingTimeInterval(1200), vitals: vitals, movement: movement)
        #expect(rows.count == 4)
        for row in rows { #expect(Set(row.values.keys) == Set(StageFeatures.Contract.podNative.columns)) }
        // Night median HRV is 30; the first epoch's HRV ratio is 20/30, the third's 40/30.
        #expect(abs(rows[0].values["hrvRel"]! - 20.0 / 30) < 1e-9)
        #expect(abs(rows[2].values["hrvRel"]! - 40.0 / 30) < 1e-9)
        // Minutes since bed entry per epoch start.
        #expect(rows.map { $0.values["minutesSinceBed"]! } == [0, 5, 10, 15])
        // The 15-minute window around epoch 0's midpoint (2:30) covers movement at 2:00.
        #expect(abs(rows[0].values["motion15"]! - log(51)) < 1e-9)
        #expect(rows[3].values["motion15"] == 0)
        // Challenger columns ride along unchanged.
        let base = StageChallenger.features(enteredBed: t0, leftBed: t0.addingTimeInterval(1200), vitals: vitals, movement: movement)
        #expect(rows.map { $0.values["hrZ"]! } == base.map { $0.values["hrZ"]! })
        #expect(StageFeatures.Contract.matching(rows[0].values.keys.sorted()) == nil)
        #expect(StageFeatures.Contract.matching(StageFeatures.Contract.podNative.columns) == .podNative)
    }

    @Test func ratiosAreZeroWithoutADenominator() {
        let vitals = (0..<10).map { vital($0, hr: 60) }
        let rows = StageFeatures.rows(contract: .podNative, enteredBed: t0, leftBed: t0.addingTimeInterval(600), vitals: vitals, movement: [])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.values["hrvRel"] == 0 && $0.values["hr15StdRel"] == 0 && $0.values["br15Std"] == 0 })
    }

    // MARK: Dataset

    @Test func labelsFollowTheScoringRuleAndDropUncoveredEpochs() {
        let epochs = [0, 5, 10, 15].map { StageChallenger.FeatureEpoch(start: t0.addingTimeInterval(Double($0) * 60), values: ["x": Double($0)]) }
        // Watch covers 0–12 minutes as light then deep. Midpoints: 2.5 light, 7.5 deep, 12.5 and 17.5 uncovered.
        let watch = [block(0, 7, .light), block(7, 12, .deep)]
        let rows = StageDataset.label(epochs, watch: watch)
        #expect(rows.map(\.label) == [.light, .deep])
        #expect(rows.map { $0.values["x"]! } == [0, 5])
        #expect(StageDataset.watchSleepSeconds(watch + [block(12, 20, .wake)]) == 12 * 60)
    }

    @Test func oversamplingLiftsRareClassesWithoutPassingTheLargest() {
        let rows = (0..<8).map { row(Double($0), .light) } + [row(8, .rem), row(9, .rem), row(10, .wake)]
        let balanced = StageDataset.oversampled(rows)
        var counts: [SleepAnalyzer.SleepStage: Int] = [:]
        for row in balanced { counts[row.label, default: 0] += 1 }
        #expect(counts[.light] == 8)
        #expect(counts[.rem] == 8)
        #expect(counts[.wake] == 8)
        // Originals keep their order at the front.
        #expect(Array(balanced.prefix(11)) == rows)
        #expect(StageDataset.oversampled([]).isEmpty)
    }

    @Test func leaveOneNightOutAndShortfalls() {
        func night(_ id: Int, rows: Int) -> StageDataset.Night {
            .init(id: id, enteredBed: t0, leftBed: t0.addingTimeInterval(3600), watch: [], rows: (0..<rows).map { row(Double($0), .light) },
                  rules: [], challenger: [])
        }
        let small = StageDataset(contract: .challenger, nights: [night(1, rows: 10), night(2, rows: 20)])
        #expect(small.shortfall?.contains("5 nights") == true)
        #expect(!small.isTrainable)
        let folds = small.leaveOneNightOut()
        #expect(folds.map { $0.heldOut.id } == [1, 2])
        #expect(folds.map { $0.training.count } == [20, 10])
        let thin = StageDataset(contract: .challenger, nights: (1...5).map { night($0, rows: 10) })
        #expect(thin.shortfall?.contains("300") == true)
        let enough = StageDataset(contract: .challenger, nights: (1...5).map { night($0, rows: 60) })
        #expect(enough.isTrainable)
        #expect(enough.labeledEpochs == 300)
    }

    @Test func trainingRefusesAFoldWithASingleClass() async throws {
        func night(_ id: Int, _ label: SleepAnalyzer.SleepStage) -> StageDataset.Night {
            .init(id: id, enteredBed: t0, leftBed: t0.addingTimeInterval(3600), watch: [], rows: (0..<70).map { row(Double($0), label) },
                  rules: [], challenger: [])
        }
        // Five nights, all light but one; holding out the deep night leaves one class.
        let dataset = StageDataset(contract: .challenger, nights: [night(1, .light), night(2, .light), night(3, .deep), night(4, .light), night(5, .light)])
        #expect(dataset.isTrainable)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stage-train-\(UUID().uuidString)")
        await #expect(throws: StageTrainer.TrainingError.self) {
            _ = try await StageTrainer.train(dataset: dataset, kind: .logistic, into: directory) { _ in }
        }
    }

    @Test func longestRecordPerDayIsTheNight() throws {
        func record(_ id: Int, enteredMinute: Int, sleepSeconds: Int) throws -> SleepRecord {
            let json = """
            {"id":\(id),"side":"left","enteredBedAt":\(Int(t0.timeIntervalSince1970) + enteredMinute * 60),"leftBedAt":\(Int(t0.timeIntervalSince1970) + enteredMinute * 60 + sleepSeconds),"sleepDurationSeconds":\(sleepSeconds)}
            """
            return try JSONDecoder().decode(SleepRecord.self, from: Data(json.utf8))
        }
        let nap = try record(1, enteredMinute: 0, sleepSeconds: 1200)
        let night = try record(2, enteredMinute: 300, sleepSeconds: 20_000)
        let nextDay = try record(3, enteredMinute: 60 * 26, sleepSeconds: 18_000)
        let chosen = StageDatasetBuilder.longestPerDay([nextDay, nap, night])
        #expect(chosen.map(\.id) == [2, 3])
    }

    // MARK: Training report and eligibility

    @Test func reportCountsNightsWonAgainstBothBaselines() {
        func score(_ kappa: Double) -> StageScore { .init(epochs: 10, accuracy: 0.5, kappa: kappa, confusion: [], recall: []) }
        let report = StageTrainingReport(kind: .forest, contract: .challenger, nights: 3, epochs: 30,
                                         pooled: score(0.3), rules: score(0.1), challenger: score(0.2),
                                         perNight: [score(0.3), score(0.1), score(0.4)],
                                         rulesPerNight: [score(0.0), score(0.2), score(0.1)],
                                         challengerPerNight: [score(0.2), nil, score(0.5)])
        // Night 1: beats both. Night 2: loses to the rules. Night 3: loses to the challenger.
        #expect(report.nightsWon == 1)
    }

    @Test func eligibilityNeedsMarginMajorityAndNights() {
        func card(lono: Double, rules: Double, challenger: Double?, nights: Int, won: Int) -> StageChallenger.Card {
            .init(version: "t", testVectors: [], model: "forest",
                  metrics: .init(lono: .init(epochs: 100, kappa: lono, accuracy: 0.5, nights: nights),
                                 rules: .init(epochs: 100, kappa: rules, accuracy: 0.4, nights: nights),
                                 challenger: challenger.map { .init(epochs: 100, kappa: $0, accuracy: 0.4, nights: nights) },
                                 nightsWon: won))
        }
        #expect(StageModelStore.isEligible(card(lono: 0.30, rules: 0.10, challenger: 0.20, nights: 6, won: 4)))
        #expect(!StageModelStore.isEligible(card(lono: 0.24, rules: 0.10, challenger: 0.20, nights: 6, won: 4)), "within the margin of the challenger")
        #expect(!StageModelStore.isEligible(card(lono: 0.30, rules: 0.10, challenger: 0.20, nights: 6, won: 3)), "no majority")
        #expect(!StageModelStore.isEligible(card(lono: 0.30, rules: 0.10, challenger: 0.20, nights: 4, won: 4)), "too few nights")
        #expect(StageModelStore.isEligible(card(lono: 0.16, rules: 0.10, challenger: nil, nights: 5, won: 3)), "no challenger is not a blocker")
        #expect(!StageModelStore.isEligible(.init(version: "t", testVectors: [])))
    }

    /// A personal model on disk is loaded through the same path as the bundled challenger, card and all.
    @Test func storeLoadsAPersonalModelFromItsDirectoryAndDeletesIt() throws {
        let bundledModel = try #require(Bundle.main.url(forResource: StageChallenger.resourceName, withExtension: "mlmodelc"))
        let bundledCardURL = try #require(Bundle.main.url(forResource: StageChallenger.cardResourceName, withExtension: "json"))
        let bundledCard = try StageChallenger.cardDecoder.decode(StageChallenger.Card.self, from: Data(contentsOf: bundledCardURL))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stage-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: bundledModel, to: StageTrainer.modelURL(for: .forest, in: directory))
        // The card the trainer would write: the bundled vectors, eligible metrics, contract A.
        let card = StageChallenger.Card(
            version: "personal-forest-test", testVectors: bundledCard.testVectors, model: "forest",
            metrics: .init(lono: .init(epochs: 500, kappa: 0.4, accuracy: 0.6, nights: 6),
                           rules: .init(epochs: 500, kappa: 0.05, accuracy: 0.3, nights: 6),
                           challenger: .init(epochs: 500, kappa: 0.1, accuracy: 0.35, nights: 6), nightsWon: 5),
            featureContract: StageChallenger.Features.columns, hyperparameters: StageModelKind.forest.hyperparameters, trainedAt: t0)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(StageTrainer.CardDocument(card)).write(to: StageTrainer.cardURL(for: .forest, in: directory))

        let defaults = try #require(UserDefaults(suiteName: "stage-store-tests-\(UUID().uuidString)"))
        defaults.set(StageModelStore.Source.personalForest.rawValue, forKey: "stageSource")
        let store = StageModelStore(defaults: defaults, directory: directory)
        #expect(store.card(for: .forest)?.version == "personal-forest-test")
        #expect(store.card(for: .forest)?.trainedAt == t0)
        #expect(store.card(for: .forest)?.metrics?.lono?.kappa == 0.4)
        #expect(store.isEligible(.forest))
        #expect(store.source == .personalForest)
        #expect(store.active?.kind == .forest)
        #expect(store.active?.contract == .challenger)
        #expect(store.activeVersion == "personal-forest-test")
        #expect(store.staging(enteredBed: t0, leftBed: t0.addingTimeInterval(3600)) != nil)
        #expect(store.card(for: .logistic) == nil)

        store.delete(.forest)
        #expect(store.card(for: .forest) == nil)
        #expect(store.source == .rules)
        #expect(store.active == nil)
        #expect(!FileManager.default.fileExists(atPath: StageTrainer.modelURL(for: .forest, in: directory).path))
    }

    @Test func storeDemotesAnIneligibleSelectionToRules() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stage-store-\(UUID().uuidString)")
        let defaults = try #require(UserDefaults(suiteName: "stage-store-tests-\(UUID().uuidString)"))
        defaults.set(StageModelStore.Source.personalLogistic.rawValue, forKey: "stageSource")
        let store = StageModelStore(defaults: defaults, directory: directory)
        #expect(store.source == .rules)
        #expect(store.personal.isEmpty)
    }

    // MARK: The analyzer with a model

    @Test func analyzerExpandsModelBlocksToMinuteEpochsAndSmoothsSpikes() throws {
        // 25 minutes of vitals: five 5-minute blocks. The model says light, light, deep, light, light; the lone
        // deep block is a spike between two lights and is smoothed away.
        let vitals = (0..<25).map { vital($0, hr: 55 + Double($0 % 3), hrv: 40) }
        let classifier = RuleClassifier { $0["nightFraction"]! >= 0.4 && $0["nightFraction"]! < 0.6 ? 2 : 1 }
        let analyzer = SleepAnalyzer()
        let staging = SleepAnalyzer.ModelStaging(classifier: classifier, contract: .challenger, enteredBed: t0, leftBed: t0.addingTimeInterval(1500))
        analyzer.analyze(vitals: vitals, movement: [], calibrationQuality: 1, model: staging)
        #expect(analyzer.source == .model)
        #expect(analyzer.stages.count == 25)
        #expect(analyzer.stages.allSatisfy { $0.duration == 60 && $0.stage == .light })
        #expect(analyzer.stages.map(\.heartRate) == vitals.map { $0.heartRate! })

        // Without smoothing a two-block run survives.
        let twoDeep = RuleClassifier { $0["nightFraction"]! >= 0.4 ? 2 : 1 }
        analyzer.analyze(vitals: vitals, movement: [], calibrationQuality: 1,
                         model: .init(classifier: twoDeep, contract: .challenger, enteredBed: t0, leftBed: t0.addingTimeInterval(1500)))
        // Separate values keep the #expect macro cheap to type-check on CI.
        let deepBlocks: Int = analyzer.stages.filter { $0.stage == .deep }.count
        #expect(deepBlocks == 15)
        // Light sits between the first light and deep already, so transition constraints change nothing here.
        let ninth: SleepAnalyzer.SleepStage = analyzer.stages[9].stage, tenth: SleepAnalyzer.SleepStage = analyzer.stages[10].stage
        #expect(ninth == .light)
        #expect(tenth == .deep)
    }

    @Test func analyzerFallsBackToRulesWhenTheModelFailsOrCalibrationIsPoor() {
        let vitals = (0..<25).map { vital($0, hr: 55 + Double($0 % 3), hrv: 40) }
        let broken = RuleClassifier { _ in 9 }
        let analyzer = SleepAnalyzer()
        analyzer.analyze(vitals: vitals, movement: [], calibrationQuality: 1,
                         model: .init(classifier: broken, contract: .challenger, enteredBed: t0, leftBed: t0.addingTimeInterval(1500)))
        #expect(analyzer.source == .rules)
        #expect(analyzer.stages.count == 25)
        let fine = RuleClassifier { _ in 2 }
        analyzer.analyze(vitals: vitals, movement: [], calibrationQuality: 0.2,
                         model: .init(classifier: fine, contract: .challenger, enteredBed: t0, leftBed: t0.addingTimeInterval(1500)))
        #expect(analyzer.source == .rules)
    }

    @Test func receiptSignatureCarriesTheModelVersion() {
        let preferences = HealthSyncService.Preferences()
        #expect(HealthSyncService.receiptSignature(preferences).contains("-mrules-"))
        #expect(HealthSyncService.receiptSignature(preferences, model: "personal-forest-x").contains("-mpersonal-forest-x-"))
        #expect(HealthSyncService.receiptSignature(preferences) != HealthSyncService.receiptSignature(preferences, model: "p"))
    }
}
