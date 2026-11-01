import SwiftUI

/// One night's stagings laid over the Apple Watch, one at a time, with every source scored against the Watch
/// on a leaderboard, and the personal models below with how they learn and whether they may stage your sleep.
struct StageComparisonView: View {
    @Environment(HealthSyncService.self) private var health
    @Environment(StageModelStore.self) private var stageModels
    let side: Side
    @State private var confirmDelete: StageModelKind?
    @State private var debugTrainingStarted = false
    @State private var modelShareItems: [URL] = []
    @State private var record: SleepRecord
    @State private var nights: [SleepRecord] = []
    @State private var comparisons: [Int: StageComparison] = [:]
    /// The touched time, shared so every lane marks the same moment.
    @State private var selection: Date?
    @State private var exportProgress: (done: Int, total: Int)?
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var exportError: String?
    /// The staging laid over the Watch; nil until the user picks one, so the app's own source opens first.
    @State private var selectedSource: StageLaneSource?
    @AppStorage("stageHowItLearnsHidden") private var howItLearnsHidden = false

    private typealias Block = StageComparison.Block
    private static let nightsBack = 30

    init(record: SleepRecord, side: Side) {
        _record = State(initialValue: record)
        self.side = side
    }

    private var isDemo: Bool { APIBackend.current.isDemo }
    private var challenger: StageChallenger.Availability { StageChallenger.bundled }
    private var needsHealthAccess: Bool { !isDemo && (!health.enabled || !health.preferences.readSleep) }
    private var comparison: StageComparison? { comparisons[record.id] }
    private var loader: StageComparisonLoader {
        StageComparisonLoader(api: APIBackend.current.createClient(), health: health, side: side, demo: isDemo, challenger: challenger,
                              personal: isDemo ? Self.demoPersonal : stageModels.personal, podModel: isDemo ? nil : stageModels.podModel)
    }
    /// Demo mode shows both personal lanes without a trained model behind them.
    private static let demoPersonal: [StageModelKind: StageChallenger.Availability] = [.logistic: .notBundled, .forest: .notBundled]
    private var builder: StageDatasetBuilder {
        StageDatasetBuilder(api: APIBackend.current.createClient(), health: health, side: side, demo: isDemo, challenger: challenger)
    }
    /// Cards with personal lanes are cached per night; a new model needs a reload, keyed by its versions.
    private var personalVersions: String {
        (StageModelKind.allCases.map { stageModels.card(for: $0)?.version ?? "-" } + [stageModels.podModel?.version ?? "-"]).joined(separator: ",")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                nightPicker.padding(.horizontal, 4)
                experimentalNote
                if needsHealthAccess { healthAccessCard }
                if let comparison {
                    let lanes = StageLanes.lanes(comparison, podTitle: stageModels.podModel?.title, challengerBundled: challenger.classifier != nil)
                    overlayCard(comparison, lanes: lanes)
                    if comparison.hasWatchData {
                        leaderboardCard(lanes)
                    } else {
                        ContentUnavailableView("No Apple Watch sleep", systemImage: "applewatch",
                                               description: Text(health.readError.map { "Health read failed: \($0)" }
                                                   ?? "No Apple Watch sleep stages overlap this night, so there is nothing to score against. Wear your Watch to bed with Sleep tracking on."))
                            .cardStyle()
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
                howItLearnsCard
                podCard
                ForEach(StageModelKind.allCases) { kind in personalCard(kind) }
                if !StageTrainer.isAvailable && !isDemo {
                    Text("Training needs an iPhone; the simulator has no Create ML.").font(.footnote).foregroundStyle(Theme.text3).padding(.horizontal, 4)
                }
                if isDemo {
                    Text("Demo mode shows synthesized personal lanes; connect a pod and wear your Watch to train real ones.")
                        .font(.footnote).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                }
                modelCard
                Text("Your Health data stays on this iPhone unless you choose to send Apple Watch readings to your own pod. sleepypod has no server: nothing goes to iCloud or anyone else.")
                    .font(.footnote).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Stage models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let exportProgress {
                    Text("\(exportProgress.done)/\(exportProgress.total)").font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
                        .accessibilityLabel("Scoring night \(exportProgress.done) of \(exportProgress.total)")
                } else {
                    Button("Share agreement", systemImage: "square.and.arrow.up") { Task { await shareAgreement() } }
                        .disabled(nights.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .sheet(isPresented: Binding(get: { !modelShareItems.isEmpty }, set: { if !$0 { modelShareItems = [] } })) {
            ShareSheet(items: modelShareItems)
        }
        .alert("Couldn't export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .alert("Training didn't finish", isPresented: Binding(get: { stageModels.trainingError != nil }, set: { if !$0 { stageModels.trainingError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(stageModels.trainingError ?? "") }
        .task { await loadNights() }
        .task {
            guard let kind = DebugRoute.trainStageModel, !isDemo, !stageModels.isTraining, !debugTrainingStarted else { return }
            debugTrainingStarted = true
            await stageModels.train(kind, builder: builder)
        }
        .onChange(of: personalVersions) { comparisons = [:] }
        .confirmationDialog("Delete this model?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let kind = confirmDelete { stageModels.delete(kind) }; confirmDelete = nil }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: { Text("Stages go back to the rules if this model was in use. You can train it again any time.") }
        .task(id: "\(record.id)-\(personalVersions)") {
            selection = nil
            // Capture the night before awaiting: switching nights cancels this
            // task, and a late result must not be cached, or cached under the new night.
            let night = record
            guard comparisons[night.id] == nil else { return }
            let comparison = await loader.load(night)
            guard !Task.isCancelled else { return }
            comparisons[night.id] = comparison
        }
    }

    // MARK: Header

    private func nightLabel(_ night: SleepRecord) -> String {
        "\(night.enteredBedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(night.bedtimeFormatted)"
    }

    private var nightPicker: some View {
        Menu {
            Picker("Night", selection: Binding(get: { record.id }, set: { id in
                if let night = nights.first(where: { $0.id == id }) { record = night }
            })) {
                ForEach(nights) { night in Text(nightLabel(night)).tag(night.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(nightLabel(record))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
        }
        .accessibilityLabel("Night, \(nightLabel(record))")
        .accessibilityIdentifier("stageNightPicker")
    }

    private var experimentalNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("EXPERIMENTAL · NOT MEDICAL", color: Theme.amber)
            Text("Several ways of staging the same night, each laid over the Watch. None of them, the pod or the Watch is a medical device, and none should guide treatment.")
                .font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var healthAccessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow sleepypod to read Sleep in Apple Health to compare with your Watch. The comparison runs on this iPhone. Sending Watch readings to your pod is optional and off unless you turn it on.")
                .font(.subheadline).foregroundStyle(Theme.text1).fixedSize(horizontal: false, vertical: true)
            NavigationLink { HealthAccessView() } label: {
                Text("Set up Apple Health").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.red)
            }
        }
        .cardStyle()
    }

    // MARK: Overlay lanes

    private static func kappaText(_ kappa: Double?) -> String { kappa.map { String(format: "%.2f", $0) } ?? "—" }
    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func selectedLane(_ lanes: [StageLane]) -> StageLane? {
        if let selectedSource, let lane = lanes.first(where: { $0.source == selectedSource }) { return lane }
        return StageLanes.initialSelection(lanes, appSource: stageModels.source).flatMap { source in lanes.first { $0.source == source } }
    }

    private func select(_ source: StageLaneSource) {
        Haptics.tap()
        withAnimation(.snappy(duration: 0.2)) { selectedSource = source }
    }

    private func overlayCard(_ comparison: StageComparison, lanes: [StageLane]) -> some View {
        let watch = WatchComparison.merged(comparison.watch, maxGap: 0)
        let lane = selectedLane(lanes)
        let bars = WatchComparison.merged(lane?.blocks ?? [], maxGap: 0)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("STAGES")
                Spacer()
                if let selection {
                    Text(readout(at: selection, watch: watch, bars: bars))
                        .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text1)
                } else {
                    Text(watch.isEmpty ? "no Watch band" : "band = Watch").font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text3)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(lanes) { candidate in
                    let selected = candidate.source == lane?.source
                    Button { select(candidate.source) } label: {
                        Text(candidate.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Theme.background : Theme.text1)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(selected ? Theme.text1 : Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border1, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            StageLaneChart(start: comparison.start, end: comparison.end, band: watch, bars: bars,
                           placeholder: lane?.placeholder ?? (watch.isEmpty && needsHealthAccess ? "Health access needed" : nil),
                           selection: selection, onSelect: { selection = $0 })
            Rectangle().fill(Theme.border1).frame(height: 1).padding(.horizontal, -18)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(lane.map { lane in
                    lane.score.map { "\(lane.title) matches the Watch on \(lane.matched) of \($0.epochs) epochs" }
                        ?? "\(lane.title) has nothing to score against the Watch"
                } ?? "Nothing staged this night")
                    .font(.subheadline).foregroundStyle(Theme.text1).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(lane?.score.map { Self.percent($0.accuracy) } ?? "—")
                    .font(.mono(24, weight: .light, relativeTo: .title2)).foregroundStyle(Theme.text1)
            }
            .accessibilityElement(children: .combine)
        }
        .cardStyle()
    }

    private func readout(at date: Date, watch: [Block], bars: [Block]) -> String {
        func text(_ blocks: [Block]) -> String { WatchComparison.stage(at: date, in: blocks)?.label ?? "—" }
        return "\(date.formatted(date: .omitted, time: .shortened))  ·  Watch \(text(watch)) / \(text(bars))"
    }

    // MARK: Leaderboard

    private func leaderboardCard(_ lanes: [StageLane]) -> some View {
        let selected = selectedLane(lanes)?.source
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Eyebrow("AGREEMENT WITH APPLE WATCH")
                Spacer()
                Text("κ").font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
            ForEach(StageLanes.ranked(lanes)) { lane in
                Button { select(lane.source) } label: {
                    HStack(spacing: 12) {
                        ModelTile(symbol: lane.source.symbol)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(lane.title).font(.subheadline).foregroundStyle(Theme.text1)
                                Spacer()
                                Text(Self.kappaText(lane.score?.kappa)).font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text1)
                            }
                            GeometryReader { proxy in
                                Capsule().fill(Theme.active)
                                Capsule().fill(Theme.text1).frame(width: proxy.size.width * min(max(lane.score?.kappa ?? 0, 0), 1))
                            }
                            .frame(height: 4)
                            Text("\(lane.source.origin) · \(lane.score.map { "\(Self.percent($0.accuracy)) match" } ?? "not scored")")
                                .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 10)
                    .background(lane.source == selected ? Theme.active.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lane.score.map { "\(lane.title): kappa \(Self.kappaText($0.kappa)), \(Self.percent($0.accuracy)) match, \($0.epochs) epochs" }
                                    ?? "\(lane.title): not scored")
                .accessibilityAddTraits(lane.source == selected ? .isSelected : [])
            }
            HStack {
                Text("0 chance")
                Spacer()
                Text("1 every epoch agrees")
            }
            .font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
            .padding(.top, 4).padding(.leading, 52).padding(.trailing, 8)
            .accessibilityHidden(true)
        }
        .cardStyle(horizontal: 10)
    }

    // MARK: How it learns

    private var howItLearnsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("HOW PERSONAL MODELS LEARN")
                Spacer()
                Button(howItLearnsHidden ? "Show" : "Hide") { withAnimation(.snappy(duration: 0.2)) { howItLearnsHidden.toggle() } }
                    .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text3)
            }
            if !howItLearnsHidden {
                HStack(alignment: .top, spacing: 6) {
                    learnStep("waveform.path.ecg", title: "Pod signals", detail: "heart rate, HRV, breathing, movement")
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.text3).padding(.top, 12)
                    learnStep("applewatch", title: "Watch labels", detail: "one stage per 5-minute epoch")
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.text3).padding(.top, 12)
                    learnStep("person", title: "Model", detail: "learns to map one to the other", inverted: true)
                }
                .accessibilityElement(children: .combine)
                Rectangle().fill(Theme.border1).frame(height: 1).padding(.horizontal, -18)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Leave-one-night-out").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text1)
                    VStack(spacing: 4) {
                        ForEach(Array(StageLanes.lonoRows(nights: lonoNights).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 3) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, scored in
                                    RoundedRectangle(cornerRadius: 3).fill(scored ? Theme.text1 : Theme.cool.opacity(0.3)).frame(height: 14)
                                }
                            }
                        }
                    }
                    .accessibilityHidden(true)
                    HStack(spacing: 12) {
                        Label { Text("train") } icon: { RoundedRectangle(cornerRadius: 2).fill(Theme.cool.opacity(0.3)).frame(width: 8, height: 8) }
                        Label { Text("score") } icon: { RoundedRectangle(cornerRadius: 2).fill(Theme.text1).frame(width: 8, height: 8) }
                    }
                    .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                    Text("Each night is scored by a model that never saw it, trained on all the others. The κ shown is the average across those runs.")
                        .font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardStyle()
    }

    /// How many nights the diagram draws: the most any model here learned from.
    private var lonoNights: Int {
        let counts = [stageModels.podModel?.metrics?["lono"]?.nights] + StageModelKind.allCases.map { stageModels.card(for: $0)?.metrics?.lono?.nights }
        return counts.compactMap { $0 }.max() ?? 10
    }

    private func learnStep(_ symbol: String, title: String, detail: String, inverted: Bool = false) -> some View {
        VStack(spacing: 6) {
            ModelTile(symbol: symbol, size: 36, inverted: inverted)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.text1)
            Text(detail).font(.caption2).foregroundStyle(Theme.text2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Model cards

    private func factRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.footnote).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(mono ? .mono(11, relativeTo: .caption2) : .footnote).foregroundStyle(mono ? Theme.text2 : Theme.text1)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func cardHeader(_ source: StageLaneSource, title: String, origin: String, pill: (text: String, color: Color)?) -> some View {
        HStack(spacing: 12) {
            ModelTile(symbol: source.symbol, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text1)
                Text(origin).font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
            }
            Spacer()
            if let pill { StatusPill(text: pill.text, color: pill.color) }
        }
        .accessibilityElement(children: .combine)
    }

    private static let changeHint = "Change in Settings › On-device analysis › Sleep stages from."

    /// The model stored on the pod, trained on a Mac in seconds; the phone evaluates it without training.
    private var podCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let model = stageModels.podModel {
                let lono = model.metrics?["lono"]
                cardHeader(.pod, title: model.title, origin: "Stored on the pod · trained on a Mac", pill: stageModels.source == .pod ? ("IN USE", Theme.green) : nil)
                VStack(spacing: 0) {
                    factRow("Trained on", "Mac, from the pod's nights")
                    factRow("Tested", "\(lono?.nights ?? 0) nights, one held out at a time")
                    factRow("Score", "κ \(Self.kappaText(lono?.kappa))", mono: true)
                    factRow("Build", model.version, mono: true)
                }
                Label(stageModels.podActive ? "Pod stages nights with this model" : "Pod uses rules",
                      systemImage: stageModels.podActive ? "checkmark.circle" : "list.bullet.rectangle")
                    .font(.footnote).foregroundStyle(stageModels.podActive ? Theme.green : Theme.text2)
            } else {
                cardHeader(.pod, title: "Pod model", origin: "Stored on the pod", pill: nil)
                Text(stageModels.podError ?? "Nothing stored on the pod yet. Train on a Mac with scripts/train-personal-models.py and it appears here.")
                    .font(.footnote).foregroundStyle(stageModels.podError == nil ? Theme.text2 : Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            Button("Refresh from pod") { Task { await stageModels.refreshPodModel(api: APIBackend.current.createClient(), side: side) } }
                .buttonStyle(CapsuleButtonStyle(weight: .tinted)).disabled(isDemo)
            Text(Self.changeHint).font(.caption2).foregroundStyle(Theme.text3)
        }
        .cardStyle()
    }

    private func personalCard(_ kind: StageModelKind) -> some View {
        let card = stageModels.card(for: kind)
        let eligible = stageModels.isEligible(kind)
        let training = stageModels.isTraining && stageModels.trainingKind == kind
        let source = StageLaneSource.personal(kind)
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader(source, title: kind.title,
                       origin: card.map { "This iPhone" + ($0.trainedAt.map { " · trained \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "") } ?? "This iPhone · not trained",
                       pill: stageModels.source.kind == kind ? ("IN USE", Theme.green) : card != nil && !eligible ? ("LEARNING", Theme.amber) : nil)
            if training { trainingProgress }
            if let card, let lono = card.metrics?.lono {
                HStack(alignment: .firstTextBaseline) {
                    Text("κ over \(lono.nights ?? 0) nights").font(.footnote).foregroundStyle(Theme.text2)
                    Spacer()
                    Text(Self.kappaText(lono.kappa)).font(.mono(28, weight: .light, relativeTo: .title)).foregroundStyle(Theme.text1)
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("TO STAGE YOUR SLEEP")
                    ForEach(StageLanes.checklist(card)) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.passed ? "checkmark" : "xmark").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.background).frame(width: 18, height: 18)
                                .background(item.passed ? Theme.green : Theme.text3, in: Circle())
                            Text(item.label).font(.footnote).foregroundStyle(Theme.text1)
                            Spacer()
                            Text(item.value).font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.passed ? "Met" : "Not met"): \(item.label), \(item.value)")
                    }
                    if let wins = card.metrics?.wonPerNight, !wins.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(Array(wins.enumerated()), id: \.offset) { _, won in
                                RoundedRectangle(cornerRadius: 2).fill(won ? Theme.green : Theme.active).frame(height: 10)
                            }
                        }
                        .padding(.leading, 28)
                        .accessibilityHidden(true)
                        Text("nights won vs both" + (card.training?.firstNight.flatMap { first in card.training?.lastNight.map { last in
                            ", \(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))" } } ?? ""))
                            .font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3).padding(.leading, 28)
                    }
                }
            } else if card == nil, !training {
                Text("Trained on this iPhone from your own nights, with the Watch as the label. Needs at least \(StageModelStore.minimumNights) nights with both.")
                    .font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(card == nil ? "Train" : "Retrain") {
                    Haptics.light()
                    Task { await stageModels.train(kind, builder: builder) }
                }
                .buttonStyle(CapsuleButtonStyle(weight: .filled))
                .disabled(stageModels.isTraining || isDemo || !StageTrainer.isAvailable)
                if card != nil {
                    Button("Share") { modelShareItems = stageModels.shareableFiles(for: kind) }
                        .buttonStyle(CapsuleButtonStyle(weight: .tinted)).disabled(stageModels.isTraining || stageModels.shareableFiles(for: kind).isEmpty)
                    Button("Delete", role: .destructive) { confirmDelete = kind }
                        .buttonStyle(CapsuleButtonStyle(weight: .plain, color: Theme.red)).disabled(stageModels.isTraining)
                }
            }
            if eligible || stageModels.source.kind == kind { Text(Self.changeHint).font(.caption2).foregroundStyle(Theme.text3) }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    private var trainingProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView().controlSize(.small)
                Text(stageModels.trainingStatus ?? "Training…").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text1)
                Spacer()
                Text("\(Int((stageModels.trainingProgress * 100).rounded()))%").font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
            }
            ProgressView(value: stageModels.trainingProgress).tint(Theme.cool)
            Text("Reads each night's vitals and movement from the pod and its stages from Health, then fits the model once per held-out night. Keep the app open.")
                .font(.footnote).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.cool.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Challenger card

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(.challenger, title: "Challenger", origin: challenger.version.map { "Research model · v\($0)" } ?? (isBundledButFailed ? "unavailable" : "not bundled"), pill: nil)
            VStack(alignment: .leading, spacing: 8) {
                if let card = challenger.card {
                    if let kappa = card.metrics?.loso?.kappa {
                        Text("Trained on \(card.training?.subjects.map(String.init) ?? "—") sleep-lab nights: agreement κ \(Self.kappaText(kappa)) (leave-one-out).")
                    }
                    if let kappa = card.metrics?.pod?.kappa {
                        Text("On the developer's pod against an Apple Watch\(card.metrics?.pod?.nights.map { " (\($0) nights)" } ?? ""): κ \(Self.kappaText(kappa)), where the pod's rules agree at about chance.")
                    }
                    if let limitations = card.limitations { Text(limitations).foregroundStyle(Theme.text3) }
                } else if case .failed(let message) = challenger {
                    Text(message)
                } else {
                    Text("This build doesn't include the model, so its lane stays empty.")
                }
                ForEach(StageChallenger.acknowledgements, id: \.self) { Text($0).foregroundStyle(Theme.text3) }
            }
            .font(.footnote).foregroundStyle(Theme.text2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var isBundledButFailed: Bool {
        if case .failed = challenger { return true }
        return false
    }

    // MARK: Data

    private func loadNights() async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -Self.nightsBack, to: end) ?? end
        let records = (try? await HealthSyncService.sleepRecords(api: APIBackend.current.createClient(), side: side, start: start, end: end)) ?? []
        var kept = records.filter { $0.side == side.rawValue && HealthSyncService.isSyncable($0) && $0.leftBedDate <= end }
        if !kept.contains(where: { $0.id == record.id }) { kept.append(record) }
        nights = kept.sorted { $0.enteredBedDate > $1.enteredBedDate }
    }

    /// Scores every night in the picker, oldest first, and shares only the de-identified summary.
    private func shareAgreement() async {
        let ordered = nights.sorted { $0.enteredBedDate < $1.enteredBedDate }
        exportProgress = (0, ordered.count)
        defer { exportProgress = nil }
        var results: [StageComparison] = []
        for night in ordered {
            if let cached = comparisons[night.id] {
                results.append(cached)
            } else {
                let loaded = await loader.load(night)
                comparisons[night.id] = loaded
                results.append(loaded)
            }
            exportProgress = (results.count, ordered.count)
        }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(StageAgreementExport.filename)
            try StageAgreementExport(nights: results, modelVersion: challenger.version).data().write(to: url, options: .atomic)
            exportURL = url
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}
