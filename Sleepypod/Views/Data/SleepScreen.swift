import SwiftUI

struct SleepScreen: View {
    enum Period: String { case night = "Night", week = "Week", month = "Month" }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(MetricsManager.self) private var metrics
    @Environment(SettingsManager.self) private var settings
    @Environment(UserProfile.self) private var profile
    @Environment(HealthSyncService.self) private var health
    @State private var selectedDate = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86400)
    @State private var period: Period = DebugRoute.current == "week" ? .week : DebugRoute.current == "month" ? .month : .night
    @State private var analyzer = SleepAnalyzer()
    @State private var agreement: Double?
    @State private var monthRecords: [SleepRecord] = []

    private var calendar: Calendar { .current }
    private var record: SleepRecord? {
        metrics.sleepRecords.first { calendar.isDate($0.enteredBedDate, inSameDayAs: selectedDate) }
    }
    private var vitals: [VitalsRecord] {
        guard let record else { return [] }
        return metrics.vitalsRecords.filter { $0.date >= record.enteredBedDate && $0.date < record.leftBedDate }
    }
    private var weekDays: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: metrics.selectedWeekStart) } }
    private var monthStart: Date { calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate }
    private var monthDays: [Date] {
        let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: monthStart) }
    }
    private var sideName: String { settings.sideName(for: metrics.selectedSide) }
    private var canMoveForward: Bool {
        let today = calendar.startOfDay(for: Date())
        switch period {
        case .night: return selectedDate < today
        case .week: return metrics.selectedWeekStart.addingTimeInterval(7 * 86400) <= today
        case .month: return (calendar.date(byAdding: .month, value: 1, to: monthStart) ?? today) <= today
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    subtitle.padding(.horizontal, 4)
                    SegmentedControl(segments: [
                        .init(value: Period.night, title: "Night"),
                        .init(value: .week, title: "Week"),
                        .init(value: .month, title: "Month")
                    ], selection: $period)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                    switch period {
                    case .night: nightContent
                    case .week: weekContent
                    case .month: monthContent
                    }
                    if let error = metrics.error {
                        Text(error).font(.footnote).foregroundStyle(Theme.amber)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Sleep")
            .settingsToolbar()
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Previous \(period.rawValue.lowercased())", systemImage: "chevron.left") { move(-1) }
                    Button("Next \(period.rawValue.lowercased())", systemImage: "chevron.right") { move(1) }
                        .disabled(!canMoveForward)
                }
            }
            .task { metrics.selectedSide = profile.defaultSide }
            .task(id: selectedDate) { await refresh() }
            .task(id: "\(period.rawValue)-\(monthStart.timeIntervalSince1970)-\(metrics.selectedSide.rawValue)") {
                if period == .month { await fetchMonth() }
            }
            .onChange(of: metrics.selectedSide) { Task { await refresh() } }
            .refreshable { await refresh(); if period == .month { await fetchMonth() } }
        }
    }

    private var subtitle: some View {
        HStack(spacing: 0) {
            Text("\(dateLabel) · ")
            Menu {
                Picker("Side", selection: Binding(get: { metrics.selectedSide }, set: { metrics.selectedSide = $0 })) {
                    ForEach(Side.allCases) { side in Text(settings.sideName(for: side)).tag(side) }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(sideName)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.text2)
            }
            .accessibilityLabel("Side, \(sideName)")
        }
        .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
        .padding(.top, -4)
    }

    private var dateLabel: String {
        switch period {
        case .night:
            return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: metrics.selectedWeekStart) ?? metrics.selectedWeekStart
            return "\(metrics.selectedWeekStart.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return monthStart.formatted(.dateTime.month(.wide).year())
        }
    }

    // MARK: Night

    @ViewBuilder private var nightContent: some View {
        if let record {
            SleepSummaryCardView(record: record, score: analyzer.qualityScore)
            SleepStagesTimelineView(stages: analyzer.stages, qualityScore: analyzer.qualityScore)
            vitalsLayout {
                vital("HR", unit: "bpm", key: \.heartRate, decimals: 0, icon: "heart", color: Theme.red)
                vital("HRV", unit: "ms", key: \.hrv, decimals: 0, icon: "waveform.path.ecg", color: Theme.cool)
                vital("BREATH", unit: "br/min", key: \.breathingRate, decimals: 1, icon: "lungs", color: Theme.green)
            }
            if health.hasWriteAuthorization && metrics.selectedSide == profile.defaultSide && !APIBackend.current.isDemo {
                healthReceipt(record)
            }
        } else if metrics.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            ContentUnavailableView("No sleep recorded", systemImage: "moon",
                                   description: Text("Choose another night to see sleep and vitals."))
        }
    }

    private var filteredVitals: [VitalsRecord] {
        vitals.filter { r in
            if let hr = r.heartRate, !hr.isFinite || !(45...130).contains(hr) { return false }
            if let hrv = r.hrv, !hrv.isFinite || !(0.001...300).contains(hrv) { return false }
            if let br = r.breathingRate, !br.isFinite || !(8...25).contains(br) { return false }
            return true
        }
    }

    private var vitalsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
    }

    private func vital(_ title: String, unit: String, key: KeyPath<VitalsRecord, Double?>, decimals: Int,
                       icon: String, color: Color) -> some View {
        let records = filteredVitals
        let values = records.compactMap { $0[keyPath: key] }
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let display = average.map { String(format: "%.\(decimals)f", $0) } ?? "—"
        return NavigationLink {
            ScrollView {
                VitalsChartCard(title: title, icon: icon, color: color, unit: unit, records: records,
                                valueKey: key, zones: [], average: nil).padding(16)
            }
            .background(Theme.background).navigationTitle(title)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(title, size: 10)
                Text(display).font(.mono(24, weight: .light, relativeTo: .title2)).foregroundStyle(Theme.text1)
                Text(unit).font(.mono(10, relativeTo: .caption2)).foregroundStyle(Theme.text3)
            }
            .cardStyle(radius: 18, vertical: 14, horizontal: 14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(display) \(unit)")
        .accessibilityHint("Shows the full chart")
    }

    private func healthReceipt(_ record: SleepRecord) -> some View {
        HStack(spacing: 10) {
            if let receipt = health.receipt(podID: settings.podID, record: record) {
                Image(systemName: "heart").font(.system(size: 15)).foregroundStyle(Theme.red)
                Text("Saved to Apple Health").font(.subheadline)
                Spacer(minLength: 8)
                Text(receipt.date.formatted(date: .omitted, time: .shortened))
                    .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.green)
            } else {
                Image(systemName: "heart").font(.system(size: 15)).foregroundStyle(Theme.amber)
                Text(health.isSyncing ? "Saving to Apple Health…" : "Not saved").font(.subheadline)
                Spacer(minLength: 8)
                Button("Retry") {
                    Task {
                        await health.syncRecent(api: APIBackend.current.createClient(), podID: settings.podID,
                                                side: profile.defaultSide, demo: APIBackend.current.isDemo)
                    }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.amber).disabled(health.isSyncing)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .cardSurface(radius: 18)
    }

    // MARK: Week

    private var weekContent: some View {
        VStack(spacing: 12) {
            let hours = weekDays.map { day in
                Double(metrics.sleepRecords.filter { calendar.isDate($0.enteredBedDate, inSameDayAs: day) }
                    .reduce(0) { $0 + $1.sleepPeriodSeconds }) / 3600
            }
            barsCard(days: weekDays, hours: hours, spacing: 10, radius: 6, height: 140) { index, day in
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? Theme.text1 : Theme.text3)
                    .opacity(index < 7 ? 1 : 0)
            }
            analysisCard
        }
    }

    private var analysisCard: some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("ON THIS iPHONE")
                Text("Stages are estimated on this iPhone from the pod's vitals, then written to Apple Health.")
                    .font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            SettingsRow("Stage model", icon: "cpu", height: 52, titleFont: .subheadline) { RowValue("rule-based", mono: true) }
            SettingsRow("Apple Health", icon: "heart", iconColor: Theme.red, height: 52, titleFont: .subheadline) {
                RowValue("\(syncedNights) of 7 nights", mono: true)
                if syncedNights > 0 && syncedNights == recordedNights {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.green)
                }
            }
            if let agreement {
                SettingsRow("Watch agreement", icon: "applewatch", height: 52, titleFont: .subheadline) {
                    RowValue("\(Int(agreement.rounded()))%", mono: true)
                }
            }
        }
    }

    private var recordedNights: Int {
        Set(metrics.sleepRecords.map { calendar.startOfDay(for: $0.enteredBedDate) }).count
    }

    private var syncedNights: Int {
        guard metrics.selectedSide == profile.defaultSide, !APIBackend.current.isDemo else { return 0 }
        return Set(metrics.sleepRecords.filter { health.receipt(podID: settings.podID, record: $0) != nil }
            .map { calendar.startOfDay(for: $0.enteredBedDate) }).count
    }

    // MARK: Month

    private var monthContent: some View {
        let hours = monthDays.map { day in
            Double(monthRecords.filter { calendar.isDate($0.enteredBedDate, inSameDayAs: day) }
                .reduce(0) { $0 + $1.sleepPeriodSeconds }) / 3600
        }
        return barsCard(days: monthDays, hours: hours, spacing: 3, radius: 3, height: 140) { _, day in
            let number = calendar.component(.day, from: day)
            Text("\(number)")
                .fixedSize()
                .frame(maxWidth: .infinity)
                .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? Theme.text1 : Theme.text3)
                .opacity([1, 8, 15, 22, 29].contains(number) ? 1 : 0)
        }
    }

    private func barsCard<Label: View>(days: [Date], hours: [Double], spacing: CGFloat, radius: CGFloat, height: CGFloat,
                                       @ViewBuilder label: @escaping (Int, Date) -> Label) -> some View {
        let recorded = hours.filter { $0 > 0 }
        let average = recorded.isEmpty ? 0 : recorded.reduce(0, +) / Double(recorded.count)
        let scale = max(8, (hours.max() ?? 0) * 1.1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("AVG ASLEEP")
                Spacer()
                Text(recorded.isEmpty ? "—" : DisplayTime.duration(Int(average * 3600)))
                    .font(.mono(24, weight: .light, relativeTo: .title2))
            }
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        let value = hours[index]
                        let selected = calendar.isDate(day, inSameDayAs: selectedDate)
                        Button {
                            Haptics.tap()
                            selectedDate = calendar.startOfDay(for: day)
                        } label: {
                            UnevenRoundedRectangle(cornerRadii: .init(topLeading: radius, bottomLeading: radius,
                                                                      bottomTrailing: radius, topTrailing: radius),
                                                   style: .continuous)
                                .fill(value > 0 ? Theme.cool.opacity(selected ? 1 : 0.75) : Theme.track)
                                .frame(height: value > 0 ? max(radius * 2, height * value / scale) : 4)
                                .frame(maxWidth: .infinity, maxHeight: height, alignment: .bottom)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
                        .accessibilityValue(value > 0 ? DisplayTime.duration(Int(value * 3600)) : "No sleep recorded")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .frame(height: height)
                HStack(spacing: spacing) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in label(index, day) }
                }
                .font(.mono(10, relativeTo: .caption2))
                .accessibilityHidden(true)
            }
        }
        .cardStyle()
    }

    // MARK: Data

    private func move(_ amount: Int) {
        let component: Calendar.Component = period == .night ? .day : period == .week ? .weekOfYear : .month
        let next = calendar.date(byAdding: component, value: amount, to: selectedDate) ?? selectedDate
        selectedDate = min(next, calendar.startOfDay(for: Date()))
        Haptics.tap()
    }

    private func fetchMonth() async {
        let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let side = metrics.selectedSide
        let records = (try? await APIBackend.current.createClient()
            .getSleepRecords(side: side, start: monthStart, end: end.addingTimeInterval(12 * 3600))) ?? []
        guard side == metrics.selectedSide else { return }
        monthRecords = records.filter { $0.side == side.rawValue && $0.enteredBedDate >= monthStart && $0.enteredBedDate < end }
    }

    private func refresh() async {
        let weekStart = calendar.startOfWeek(for: selectedDate)
        if metrics.selectedWeekStart != weekStart { metrics.selectedWeekStart = weekStart }
        await metrics.fetchAll()
        let calibration = try? await APIBackend.current.createClient().getCalibrationStatus(side: metrics.selectedSide)
        analyzer.analyze(vitals: vitals, movement: metrics.movementRecords, calibrationQuality: calibration?.piezo?.qualityScore ?? 0)
        let weekAnalyzer = SleepAnalyzer()
        var weekEpochs: [SleepAnalyzer.SleepEpoch] = []
        for night in metrics.sleepRecords where night.leftBedDate > night.enteredBedDate {
            let records = metrics.vitalsRecords.filter { $0.date >= night.enteredBedDate && $0.date < night.leftBedDate }
            weekAnalyzer.analyze(vitals: records, movement: metrics.movementRecords, calibrationQuality: calibration?.piezo?.qualityScore ?? 0)
            weekEpochs.append(contentsOf: weekAnalyzer.stages)
        }
        agreement = await health.watchAgreement(epochs: weekEpochs.sorted { $0.start < $1.start })
    }
}
