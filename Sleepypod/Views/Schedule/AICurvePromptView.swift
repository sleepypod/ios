import SwiftUI

/// Natural language curve generation sheet.
/// User describes preferences → AI generates temperature set points.
struct AICurvePromptView: View {
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var generator = CurveGenerator()
    @State private var prompt = ""
    @State private var isApplied = false
    @FocusState private var isFocused: Bool

    private let suggestions = [
        "I run hot, bed at 11pm, wake 6:30. Really cold first few hours.",
        "Light sleeper, cold feet. Warm start, gentle cooling, warm wake at 7am.",
        "Post-workout recovery. Bed 10pm, wake 6am. Extra cold for muscles.",
        "I'm always cold. Minimal cooling, cozy all night. Bed 11:30, wake 7:30.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Prompt input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe your ideal sleep temperature")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)

                        TextField("e.g., I run hot, bed at 11pm...", text: $prompt, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .focused($isFocused)

                        // Quick suggestions
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button {
                                        Haptics.light()
                                        prompt = suggestion
                                    } label: {
                                        Text(suggestion)
                                            .font(.caption2)
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(1)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Theme.cardElevated)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Generate button
                    Button {
                        Haptics.medium()
                        isFocused = false
                        Task { await generator.generate(prompt: prompt) }
                    } label: {
                        HStack(spacing: 8) {
                            if generator.isGenerating {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(generator.isGenerating ? "Generating…" : "Generate Curve")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(prompt.isEmpty ? Theme.textMuted : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.isEmpty || generator.isGenerating)

                    // Error
                    if let error = generator.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Theme.amber)
                    }

                    // Result
                    if let result = generator.lastResult {
                        resultCard(result)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("AI Curve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Result Card

    private func resultCard(_ result: CurveGenerator.GeneratedCurve) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundColor(Theme.accent)
                Text(result.profileName.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
                Spacer()
                Text("\(result.bedtime) → \(result.wake)")
                    .font(.caption2.monospaced())
                    .foregroundColor(Theme.textMuted)
            }

            // Reasoning
            Text(result.reasoning)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)

            // Set points preview
            let sorted = result.points.sorted { $0.key < $1.key }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sorted, id: \.key) { time, temp in
                        VStack(spacing: 2) {
                            Text("\(temp)°")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(tempColor(temp))
                            Text(time)
                                .font(.system(size: 8).monospaced())
                                .foregroundColor(Theme.textMuted)
                        }
                        .frame(width: 40)
                        .padding(.vertical, 6)
                        .background(Theme.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Apply button
            Button {
                Haptics.heavy()
                applyResult(result)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isApplied ? "checkmark" : "arrow.down.to.line")
                    Text(isApplied ? "Applied" : "Apply to Schedule")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isApplied ? Theme.healthy : Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isApplied)
        }
        .cardStyle()
    }

    private func tempColor(_ tempF: Int) -> Color {
        let offset = tempF - 80
        return TempColor.forOffset(offset)
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
            } catch {
                Log.general.error("Failed to apply AI curve: \(error)")
            }
        }
    }
}
