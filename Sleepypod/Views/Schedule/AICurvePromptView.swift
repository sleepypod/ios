import SwiftUI
import Charts

/// Horizontal paged AI curve builder.
/// 4 steps: Describe -> Review -> Import -> Apply.
struct AICurvePromptView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss

    var startPage: Int = 0

    @State private var generator = CurveGenerator()
    @State private var prompt = ""
    @State private var generatedPrompt = ""
    @State private var pastedJSON = ""
    @State private var parsedResult: CurveGenerator.GeneratedCurve?
    @State private var editablePoints: [SetPoint] = []
    @State private var isApplied = false
    @State private var copiedPrompt = false
    @State private var copiedJSON = false
    @State private var showSaveDialog = false
    @State private var templateName = ""
    @State private var savedTemplates: [CurveTemplate] = []
    @State private var currentPage: Int = 0
    @State private var didInitialSetup = false
    @State private var parseError: String?
    @State private var showManualField = false
    @FocusState private var isFocused: Bool
    @FocusState private var isJSONFocused: Bool

    private let stepCount = 4

    private let suggestions = [
        "I run hot, bed at 11pm, wake 6:30. Really cold first few hours.",
        "Light sleeper, cold feet. Warm start, gentle cooling, warm wake at 7am.",
        "Post-workout recovery. Bed 10pm, wake 6am. Extra cold for muscles.",
        "I'm always cold. Minimal cooling, cozy all night. Bed 11:30, wake 7:30.",
    ]

    private let stepLabels = ["Describe", "Review", "Import", "Apply"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                stepIndicator
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Paged content
                TabView(selection: $currentPage) {
                    describePage.tag(0)
                    promptPage.tag(1)
                    pastePage.tag(2)
                    previewPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: currentPage) { oldValue, newValue in
                    guard didInitialSetup else { return }
                    // Prevent forward swiping past the highest unlocked step
                    let maxAllowed = highestUnlockedPage
                    if newValue > maxAllowed {
                        currentPage = oldValue
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Design Your Curve")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                savedTemplates = CurveTemplate.loadAll()
                if startPage > 0 {
                    generatedPrompt = " " // unlock navigation
                    currentPage = startPage
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    didInitialSetup = true
                }
            }
            .alert("Save Template", isPresented: $showSaveDialog) {
                TextField("Template name", text: $templateName)
                Button("Save") { saveAsTemplate() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give this curve a name so you can reuse it later.")
            }
        }
    }

    /// The highest page the user is allowed to reach based on completed steps.
    private var highestUnlockedPage: Int {
        if parsedResult != nil { return 3 }
        if !generatedPrompt.isEmpty { return 2 }
        return 0
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<stepCount, id: \.self) { index in
                let isActive = index == currentPage
                let isCompleted = index < currentPage
                let isTappable = index <= highestUnlockedPage && index < currentPage

                Button {
                    if isTappable {
                        Haptics.light()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentPage = index
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(isActive ? Theme.accent : isCompleted ? Theme.accent.opacity(0.4) : Theme.textMuted.opacity(0.3))
                                .frame(width: 20, height: 20)
                            if isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(isActive ? .white : Theme.textMuted)
                            }
                        }
                        Text(stepLabels[index])
                            .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                            .foregroundColor(isActive ? Theme.accent : isCompleted ? Theme.textSecondary : Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isTappable)

                if index < stepCount - 1 {
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Theme.textMuted.opacity(0.4))
                    Spacer(minLength: 2)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Page 1: Describe

    private var describePage: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Describe your sleep preferences")
                        .font(.headline)
                        .foregroundColor(.white)

                    TextField("e.g., I run hot, bed at 11pm...", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .focused($isFocused)

                    // Example suggestion cards
                    Text("or try an example:")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)

                    VStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                Haptics.light()
                                prompt = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Theme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Theme.cardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer(minLength: 120)
                }
                .padding(16)
            }

            floatingBar {
                floatingButton(title: "Next", icon: "arrow.right") {
                    Haptics.medium()
                    isFocused = false
                    generatedPrompt = generator.generatePrompt(preferences: prompt)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentPage = 1
                    }
                }
                .opacity(prompt.isEmpty ? 0.4 : 1.0)
                .disabled(prompt.isEmpty)
            }
        }
    }

    // MARK: - Page 2: Prompt

    private var promptPage: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Review & Copy")
                        .font(.headline)
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption2)
                            Text("Tap **Share** to send directly to ChatGPT, Claude, or Gemini.")
                                .font(.caption2)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.caption2)
                            Text("Or **Copy** and paste into any AI tool.")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(Theme.textMuted)

                    Text(generatedPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 120)
                }
                .padding(16)
            }

            floatingBar {
                // Copy
                floatingButton(title: copiedPrompt ? "Copied!" : "Copy", icon: copiedPrompt ? "checkmark" : "doc.on.clipboard") {
                    UIPasteboard.general.string = generatedPrompt
                    withAnimation { copiedPrompt = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copiedPrompt = false } }
                }

                Divider().frame(height: 20).background(Color.white.opacity(0.2))

                // Share (manual UIActivityViewController to avoid ShareLink freeze)
                floatingButton(title: "Share", icon: "square.and.arrow.up") {
                    let av = UIActivityViewController(activityItems: [generatedPrompt], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = windowScene.windows.first?.rootViewController {
                        // Find the topmost presented controller
                        var topVC = root
                        while let presented = topVC.presentedViewController { topVC = presented }
                        av.popoverPresentationController?.sourceView = topVC.view
                        av.popoverPresentationController?.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.maxY - 100, width: 0, height: 0)
                        topVC.present(av, animated: true)
                    }
                }

                Divider().frame(height: 20).background(Color.white.opacity(0.2))

                // Next
                floatingButton(title: "Next", icon: "arrow.right") {
                    copiedPrompt = true
                    withAnimation(.easeInOut(duration: 0.25)) { currentPage = 2 }
                }
            }
        }
    }

    // MARK: - Page 3: Paste

    private var pastePage: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Import Results")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Copy the AI response to your clipboard, then tap Paste below.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)

                    // Manual field (always visible as fallback)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Or paste manually")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)

                        TextField("Paste JSON here...", text: $pastedJSON, axis: .vertical)
                            .lineLimit(5...12)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(12)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.cardBorder, lineWidth: 1)
                            )
                            .focused($isJSONFocused)
                            .onChange(of: pastedJSON) { _, newValue in
                                parseError = nil
                                // Auto-parse if it looks like JSON
                                if newValue.contains("{") && newValue.contains("}") {
                                    // Debounce
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(500))
                                        if pastedJSON == newValue { // still same text
                                            attemptParse()
                                        }
                                    }
                                }
                            }

                        if !pastedJSON.isEmpty {
                            Button {
                                Haptics.medium()
                                isJSONFocused = false
                                attemptParse()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.right.circle.fill")
                                    Text("Parse & Continue")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Error display
                    if let parseError {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(parseError)
                                .font(.caption)
                        }
                        .foregroundColor(Theme.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.amber.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer(minLength: 120)
                }
                .padding(16)
            }

            floatingBar {
                floatingButton(title: "Paste from Clipboard", icon: "doc.on.clipboard.fill") {
                    if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                        pastedJSON = clipboard
                        attemptParse()
                    }
                }
            }
        }
    }

    // MARK: - Page 4: Preview & Apply

    private var previewPage: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if parsedResult != nil {
                        // Bedtime / wake badge
                        if let result = parsedResult {
                            HStack {
                                Text("Preview & Edit")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(result.bedtime) \u{2192} \(result.wake)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(Theme.textMuted)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Theme.cardElevated)
                                    .clipShape(Capsule())
                            }
                        }

                        // AI reasoning
                        if let result = parsedResult, !result.reasoning.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption)
                                    .foregroundColor(Theme.accent)
                                    .padding(.top, 1)
                                Text(result.reasoning)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .padding(10)
                            .background(Theme.accent.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Temperature curve chart
                        curveChart
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Phase legend
                        phaseLegend

                        // Editable set points
                        SetPointEditor(
                            points: $editablePoints,
                            temperatureFormat: settingsManager.temperatureFormat,
                            onChanged: { syncResultFromEdits() }
                        )

                        // Error display
                        if let error = generator.error {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                Text(error)
                                    .font(.caption)
                            }
                            .foregroundColor(Theme.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        // Placeholder when no result yet
                        VStack(spacing: 12) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.largeTitle)
                                .foregroundColor(Theme.textMuted)
                            Text("Complete the previous steps to preview your curve.")
                                .font(.subheadline)
                                .foregroundColor(Theme.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 80)
                    }

                    Spacer(minLength: 120)
                }
                .padding(16)
            }

            floatingBar {
                floatingButton(title: "Save", icon: "bookmark") {
                    templateName = parsedResult?.profileName ?? ""
                    showSaveDialog = true
                }

                Divider().frame(height: 20).background(Color.white.opacity(0.2))

                floatingButton(title: isApplied ? "Applied!" : "Apply", icon: isApplied ? "checkmark" : "calendar.badge.plus") {
                    applyToSchedule()
                }
            }
        }
    }

    // MARK: - Saved Templates

    private var templateChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundColor(Theme.accent)
                Text("SAVED TEMPLATES")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(savedTemplates) { template in
                        Button {
                            Haptics.light()
                            loadTemplate(template)
                        } label: {
                            HStack(spacing: 6) {
                                Text(template.name)
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                Button {
                                    Haptics.light()
                                    deleteTemplate(template)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(Theme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.cardElevated)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Curve Chart

    private var curveChart: some View {
        let sorted = editablePoints.sorted { $0.time < $1.time }
        let temps = sorted.map(\.tempF)
        let minTemp = temps.min() ?? 70
        let maxTemp = temps.max() ?? 90
        let offsets = sorted.map { $0.tempF - 80 }
        let lo = (offsets.min() ?? -10) - 3
        let hi = (offsets.max() ?? 10) + 3

        return Chart {
            // Zero line (base temp ~80F)
            RuleMark(y: .value("Base", 0))
                .foregroundStyle(Theme.textMuted.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Min dashed rule
            RuleMark(y: .value("Min", minTemp - 80))
                .foregroundStyle(Theme.cooling.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

            // Max dashed rule
            RuleMark(y: .value("Max", maxTemp - 80))
                .foregroundStyle(Theme.warming.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

            ForEach(sorted) { point in
                let offset = point.tempF - 80
                let color = phaseColor(point.phase)

                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Offset", offset)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))

                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Offset", offset)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.2), Color.clear],
                        startPoint: offset > 0 ? .top : .bottom,
                        endPoint: offset > 0 ? .bottom : .top
                    )
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Time", point.time),
                    y: .value("Offset", offset)
                )
                .foregroundStyle(color)
                .symbolSize(20)
            }
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    .foregroundStyle(Theme.cardBorder)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        let format = settingsManager.temperatureFormat
                        if format == .relative {
                            Text(v > 0 ? "+\(v)" : "\(v)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                        } else {
                            Text(TemperatureConversion.displayTemp(80 + v, format: format))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel {
                    if let time = value.as(String.self) {
                        Text(time)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                            .rotationEffect(.degrees(-45))
                            .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - Phase Legend

    private var phaseLegend: some View {
        let phases: [(name: String, color: Color)] = [
            ("Warm-up", Theme.warming),
            ("Cool-down", Theme.cooling),
            ("Deep Sleep", Color(hex: "2563eb")),
            ("Maintain", Theme.textSecondary),
            ("Pre-Wake", Theme.amber),
        ]
        return HStack(spacing: 10) {
            ForEach(phases, id: \.name) { phase in
                HStack(spacing: 4) {
                    Circle().fill(phase.color).frame(width: 6, height: 6)
                    Text(phase.name)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Floating Bar

    private func floatingBar(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

        }
        .padding(.bottom, 20)
    }

    private func floatingButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func attemptParse() {
        parseError = nil
        isJSONFocused = false

        if let result = generator.parse(json: pastedJSON) {
            applyParsedResult(result)
            // Auto-advance to page 4
            withAnimation(.easeInOut(duration: 0.25)) {
                currentPage = 3
            }
        } else {
            parseError = generator.error ?? "Could not parse JSON. Make sure you pasted the complete AI response."
        }
    }

    private func phaseColor(_ phase: String) -> Color {
        let lower = phase.lowercased()
        if lower.contains("warm") && lower.contains("up") { return Theme.warming }
        if lower.contains("cool") { return Theme.cooling }
        if lower.contains("deep") { return Color(hex: "2563eb") }
        if lower.contains("maintain") { return Theme.textSecondary }
        if lower.contains("pre") && lower.contains("wake") { return Theme.amber }
        if lower.contains("wake") { return Theme.textMuted }
        return Theme.textSecondary
    }

    private func classifyPhase(time: String, bedtime: String, wake: String, tempF: Int, allPoints: [(String, Int)]) -> String {
        let sorted = allPoints.sorted { $0.0 < $1.0 }
        guard let minTemp = sorted.map(\.1).min(),
              let maxTemp = sorted.map(\.1).max() else { return "Maintain" }

        let midpoint = (minTemp + maxTemp) / 2

        if time < bedtime { return "Warm-up" }
        if time >= wake { return "Wake" }

        let allTimes = sorted.filter { $0.0 >= bedtime && $0.0 < wake }.map(\.0)
        let totalPoints = allTimes.count
        if let idx = allTimes.firstIndex(of: time) {
            let position = Double(idx) / max(Double(totalPoints - 1), 1.0)
            if position < 0.25 { return "Cool-down" }
            if position < 0.55 { return "Deep Sleep" }
            if position < 0.8 { return "Maintain" }
            return "Pre-Wake"
        }

        if tempF <= midpoint { return "Deep Sleep" }
        return "Maintain"
    }

    private func applyParsedResult(_ result: CurveGenerator.GeneratedCurve) {
        parsedResult = result
        let allPoints = result.points.map { ($0.key, $0.value) }
        editablePoints = result.points.map { time, temp in
            let phase = classifyPhase(
                time: time,
                bedtime: result.bedtime,
                wake: result.wake,
                tempF: temp,
                allPoints: allPoints
            )
            return SetPoint(time: time, tempF: temp, phase: phase)
        }.sorted { $0.time < $1.time }

        generator.error = nil
    }

    private func syncResultFromEdits() {
        guard let old = parsedResult else { return }
        var newPoints: [String: Int] = [:]
        for p in editablePoints {
            newPoints[p.time] = p.tempF
        }
        parsedResult = CurveGenerator.GeneratedCurve(
            bedtime: old.bedtime,
            wake: old.wake,
            points: newPoints,
            reasoning: old.reasoning,
            profileName: old.profileName
        )
        generator.lastResult = parsedResult
        isApplied = false
    }

    // MARK: - Template Actions

    private func loadTemplate(_ template: CurveTemplate) {
        let result = CurveGenerator.GeneratedCurve(
            bedtime: template.bedtime,
            wake: template.wake,
            points: template.points,
            reasoning: template.reasoning,
            profileName: template.name
        )
        generator.lastResult = result
        applyParsedResult(result)
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage = 3
        }
    }

    private func deleteTemplate(_ template: CurveTemplate) {
        CurveTemplate.delete(named: template.name)
        savedTemplates = CurveTemplate.loadAll()
    }

    private func saveAsTemplate() {
        guard let result = parsedResult, !templateName.isEmpty else { return }
        var points: [String: Int] = [:]
        for p in editablePoints {
            points[p.time] = p.tempF
        }
        let template = CurveTemplate(
            name: templateName,
            points: points,
            bedtime: result.bedtime,
            wake: result.wake,
            reasoning: result.reasoning
        )
        CurveTemplate.add(template)
        savedTemplates = CurveTemplate.loadAll()
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }

    // MARK: - Apply to Schedule

    private func applyToSchedule() {
        guard let result = parsedResult else { return }
        var finalPoints: [String: Int] = [:]
        for p in editablePoints {
            finalPoints[p.time] = p.tempF
        }
        let finalResult = CurveGenerator.GeneratedCurve(
            bedtime: result.bedtime,
            wake: result.wake,
            points: finalPoints,
            reasoning: result.reasoning,
            profileName: result.profileName
        )
        applyResult(finalResult)
    }

    private func applyResult(_ result: CurveGenerator.GeneratedCurve) {
        Task {
            guard var schedules = scheduleManager.schedules else { return }
            let side = scheduleManager.selectedSide.primarySide

            for day in scheduleManager.selectedDays {
                var sideSchedule = schedules.schedule(for: side)
                var daily = sideSchedule[day]
                daily.temperatures = result.points
                daily.power.on = result.bedtime
                daily.power.off = result.wake
                daily.power.enabled = true
                daily.alarm.time = result.wake
                daily.alarm.enabled = true
                sideSchedule[day] = daily
                schedules.setSchedule(sideSchedule, for: side)

                if scheduleManager.selectedSide == .both {
                    var other = schedules.schedule(for: side == .left ? .right : .left)
                    other[day] = daily
                    schedules.setSchedule(other, for: side == .left ? .right : .left)
                }
            }

            scheduleManager.schedules = schedules
            do {
                let api = APIBackend.current.createClient()
                scheduleManager.schedules = try await api.updateSchedules(schedules, days: scheduleManager.selectedDays)
                withAnimation { isApplied = true }
                Haptics.success()
            } catch {
                Log.general.error("Failed to apply AI curve: \(error)")
            }
        }
    }
}
