import SwiftUI

struct ScheduleScreen: View {
    @Environment(ScheduleManager.self) private var schedule
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editingPhase: SchedulePhase?
    @State private var alarmEditor = false
    @State private var showCurvePicker = false
    @State private var showDesigner = false

    private var daily: DailySchedule? { schedule.currentDailySchedule }
    private var points: [RunOnceSetPoint] { schedule.phases.map { RunOnceSetPoint(time: $0.time, temperature: Double($0.temperatureF)) } }
    private var profile: String {
        let temps = points.map { Int($0.temperature) }.sorted()
        return SleepProfile.allCases.first { $0.temperatures(for: temps.count).sorted() == temps }?.rawValue ?? "Custom"
    }

    private var bedTemperature: Int { TemperatureConversion.baseTempF }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DaySelectorView().padding(.horizontal, 4)
                    if let daily {
                        curveCard(daily)
                        phaseList(daily)
                        GroupedCard {
                            SettingsRow("Schedule active", icon: "power") {
                                Toggle("Schedule active", isOn: Binding(get: { daily.power.enabled }, set: { _ in
                                    Task { await schedule.togglePowerSchedule() }
                                })).labelsHidden().tint(Theme.green)
                            }
                            if settings.supportsScheduleEndAction {
                                Menu {
                                    Picker("At wake", selection: Binding(get: { daily.power.endAction ?? .turnOff }, set: { action in
                                        Task { await schedule.setPowerEndAction(action) }
                                    })) {
                                        ForEach(ScheduleEndAction.allCases, id: \.self) { Text($0.label).tag($0) }
                                    }
                                } label: {
                                    SettingsRow("At wake", icon: "sun.max", chevron: true) { RowValue((daily.power.endAction ?? .turnOff).label) }
                                }
                                .buttonStyle(.plain)
                            }
                            Menu {
                                ForEach(SleepProfile.allCases) { profile in
                                    Button(profile.rawValue) { Task { await schedule.applyProfile(profile) } }
                                }
                                Divider()
                                Button("Design a curve", systemImage: "wand.and.stars") { showDesigner = true }
                            } label: {
                                SettingsRow("Sleep profile", icon: "slider.horizontal.3", chevron: true) { RowValue(profile) }
                            }
                            .buttonStyle(.plain)
                        }
                    } else if schedule.isLoading {
                        ProgressView().padding(.top, 40)
                    } else {
                        ContentUnavailableView("No schedule", systemImage: "calendar",
                                               description: Text(schedule.error ?? "Pull to refresh your pod's schedule."))
                    }
                    if let error = schedule.error, daily != nil {
                        Text(error).font(.footnote).foregroundStyle(Theme.amber).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Schedule")
            .settingsToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Side", selection: Binding(get: { schedule.selectedSide }, set: { schedule.selectedSide = $0 })) {
                            Text(settings.leftName).tag(SideSelection.left)
                            Label("Both", systemImage: "link").tag(SideSelection.both)
                            Text(settings.rightName).tag(SideSelection.right)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(schedule.selectedSide == .both ? "Both" : settings.sideName(for: schedule.selectedSide.primarySide))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text1)
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                        }
                        .padding(.horizontal, 6)
                    }
                    .accessibilityLabel("Side")
                }
            }
            .sheet(item: $editingPhase) { phase in
                SetPointEditor(phase: phase).presentationDetents([.medium])
            }
            .sheet(isPresented: $alarmEditor) {
                if let alarm = daily?.alarm { AlarmEditorSheet(alarm: alarm).presentationDetents([.medium, .large]) }
            }
            .sheet(isPresented: $showDesigner) {
                NavigationStack {
                    ScrollView { SmartCurveView(showCurvePicker: $showCurvePicker).padding() }
                        .background(Theme.background)
                        .navigationTitle("Design a curve")
                        .navigationBarTitleDisplayMode(.inline)
                        .sheet(isPresented: $showCurvePicker) { CurveLibraryView() }
                }
            }
            .task { await schedule.fetchSchedules() }
            .refreshable { await schedule.fetchSchedules() }
        }
    }

    private func curveCard(_ daily: DailySchedule) -> some View {
        let minutes = (DisplayTime.minutes(daily.power.off) - DisplayTime.minutes(daily.power.on) + 1440) % 1440
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow("\(profile.uppercased()) · \(DisplayTime.duration(minutes * 60))")
                Spacer()
                Text(settings.temperatureFormat == .celsius ? "°C" : "°F")
                    .font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text3)
            }
            TemperatureCurve(points: points, bedtime: daily.power.on, wake: daily.power.off, bedTemperature: bedTemperature)
        }
        .cardStyle()
    }

    private func phaseList(_ daily: DailySchedule) -> some View {
        GroupedCard {
            ForEach(schedule.phases) { phase in
                Button { editingPhase = phase } label: {
                    phaseRow(icon: phase.icon, name: phase.name, time: phase.time, temperature: phase.temperatureF)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit set point")
            }
            Button { alarmEditor = true } label: {
                phaseRow(icon: "alarm",
                         name: "Wake",
                         time: daily.alarm.enabled ? daily.alarm.time : daily.power.off,
                         temperature: daily.alarm.enabled ? daily.alarm.alarmTemperature : nil)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit alarm")
        }
    }

    private func phaseRow(icon: String, name: String, time: String, temperature: Int?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.icon).frame(width: 22)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Text(name).font(.callout).foregroundStyle(Theme.text1)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(DisplayTime.clock(time)).font(.mono(13, relativeTo: .footnote)).foregroundStyle(Theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let temperature {
                    Text(phaseTemperature(temperature)).foregroundStyle(TempColor.forScheduled(temperature))
                } else {
                    Text("Off").foregroundStyle(Theme.text3)
                }
            }
            .font(.mono(15, relativeTo: .subheadline))
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    /// Rows show the bare degree ("76°"); the unit sits once in the curve header.
    private func phaseTemperature(_ tempF: Int) -> String {
        switch settings.temperatureFormat {
        case .fahrenheit: "\(tempF)°"
        case .celsius: "\(Int(TemperatureConversion.tempFToC(tempF).rounded()))°"
        case .relative: TemperatureConversion.offsetDisplay(tempF - TemperatureConversion.baseTempF)
        }
    }
}

private struct AlarmEditorSheet: View {
    @State var alarm: AlarmSchedule
    @Environment(ScheduleManager.self) private var schedule
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Alarm", isOn: $alarm.enabled)
                DatePicker("Wake time", selection: $time, displayedComponents: .hourAndMinute).datePickerStyle(.wheel)
                Picker("Pattern", selection: $alarm.vibrationPattern) {
                    Text("Rise").tag(VibrationPattern.rise)
                    Text("Double").tag(VibrationPattern.double)
                }
                Stepper("\(alarm.duration)s buzz", value: $alarm.duration, in: 1...180, step: 1)
                Slider(value: Binding(get: { Double(alarm.vibrationIntensity) }, set: { alarm.vibrationIntensity = Int($0) }), in: 1...100) { Text("Intensity") }
            }.tint(Theme.green).navigationTitle("Alarm").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    let f = DateFormatter(); f.dateFormat = "HH:mm"; alarm.time = f.string(from: time)
                    Task { await schedule.updateAlarmSchedule(alarm); if schedule.error == nil { dismiss() } }
                } } }
                .onAppear { time = Calendar.current.date(bySettingHour: DisplayTime.minutes(alarm.time) / 60, minute: DisplayTime.minutes(alarm.time) % 60, second: 0, of: Date()) ?? Date() }
        }
    }
}

private struct CurveLibraryView: View {
    @Environment(ScheduleManager.self) private var schedule
    @Environment(\.dismiss) private var dismiss
    @State private var templates = CurveTemplate.loadAll()
    var body: some View {
        NavigationStack {
            List {
                Section("Saved curves") {
                    ForEach(templates) { template in
                        Button(template.name) {
                            Task { if await schedule.applyTemplate(template) { dismiss() } }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { CurveTemplate.delete(named: templates[index].name) }
                        templates = CurveTemplate.loadAll()
                    }
                    if templates.isEmpty { Text("No saved curves").foregroundStyle(Theme.text2) }
                }
                NavigationLink("Design your own") { AICurvePromptView(startPage: 0) }
                NavigationLink("Import a curve") { AICurvePromptView(startPage: 2) }
                if let error = schedule.error { Text(error).foregroundStyle(Theme.amber) }
            }.navigationTitle("Curves").onAppear { templates = CurveTemplate.loadAll() }
        }
    }
}
