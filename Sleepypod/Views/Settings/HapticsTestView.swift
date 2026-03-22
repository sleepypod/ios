import SwiftUI

// MARK: - Vibration Pattern Model

private struct VibrationPreset: Identifiable {
    let id = UUID()
    let name: String
    let intensity: Int
    let pattern: VibrationPattern
    let duration: Int
    let description: String
}

private let samplePatterns: [VibrationPreset] = [
    VibrationPreset(name: "Gentle Wake", intensity: 30, pattern: .rise, duration: 10, description: "Soft rising vibration"),
    VibrationPreset(name: "Standard Alarm", intensity: 50, pattern: .rise, duration: 30, description: "Default alarm pattern"),
    VibrationPreset(name: "Urgent Wake", intensity: 80, pattern: .double, duration: 15, description: "Strong double-burst"),
    VibrationPreset(name: "Nudge", intensity: 20, pattern: .double, duration: 3, description: "Quick gentle tap"),
    VibrationPreset(name: "Pulse Train", intensity: 60, pattern: .double, duration: 20, description: "Repeated double bursts"),
    VibrationPreset(name: "Deep Sleeper", intensity: 100, pattern: .rise, duration: 60, description: "Maximum intensity ramp"),
    VibrationPreset(name: "Meditation End", intensity: 15, pattern: .rise, duration: 5, description: "Barely noticeable fade-in"),
]

// MARK: - View

struct HapticsTestView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @State private var selectedSide: SideSelection = .left
    @State private var isVibrating = false
    @State private var activePresetID: UUID?
    @State private var errorMessage: String?

    // Custom vibration state
    @State private var customIntensity: Double = 50
    @State private var customPattern: VibrationPattern = .rise
    @State private var customDuration: Double = 10
    @State private var showCustom = false

    private var api: SleepypodProtocol {
        APIBackend.current.createClient()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Side selector
                sideSelector

                // Preset patterns
                presetsSection

                // Custom section
                customSection

                // Stop button
                stopButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .navigationTitle("Haptics & Vibration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedSide = deviceManager.selectedSide
        }
        .onDisappear {
            if isVibrating {
                Task { await stopAllVibration() }
            }
        }
    }

    // MARK: - Side Selector

    private var sideSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TARGET SIDE")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            HStack(spacing: 0) {
                sideButton(.left, label: "Left")
                sideButton(.right, label: "Right")
                sideButton(.both, label: "Both")
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .cardStyle()
    }

    private func sideButton(_ side: SideSelection, label: String) -> some View {
        let isSelected = selectedSide == side
        return Button {
            Haptics.tap()
            selectedSide = side
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(isSelected ? Theme.cooling : Theme.cardElevated)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Presets

    @State private var showPresets = false

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) { showPresets.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accent)
                    Text("VIBRATION PATTERNS")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(1)
                    Spacer()
                    Text("\(samplePatterns.count) presets")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(showPresets ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showPresets {
                ForEach(samplePatterns) { preset in
                    presetRow(preset)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(Theme.error)
                    .transition(.opacity)
            }
        }
        .cardStyle()
    }

    private func presetRow(_ preset: VibrationPreset) -> some View {
        let isActive = activePresetID == preset.id
        return HStack(spacing: 12) {
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    Text("\(preset.duration)s")
                        .font(.caption.monospaced())
                        .foregroundColor(Theme.textMuted)
                    Text(preset.pattern == .double ? "Double" : "Rise")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            Spacer()

            // Intensity bar
            intensityBar(value: preset.intensity)
                .frame(width: 40, height: 16)

            // Play button
            Button {
                Haptics.medium()
                Task { await triggerPreset(preset) }
            } label: {
                Image(systemName: isActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? Theme.error : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(isActive ? Theme.error.opacity(0.15) : Theme.accent.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func intensityBar(value: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.textMuted.opacity(0.1))
                RoundedRectangle(cornerRadius: 3)
                    .fill(intensityColor(value))
                    .frame(width: geo.size.width * CGFloat(value) / 100)
            }
        }
    }

    private func intensityColor(_ value: Int) -> Color {
        if value <= 33 { return Theme.healthy }
        if value <= 66 { return Theme.amber }
        return Theme.error
    }

    // MARK: - Custom Section

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showCustom.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.purple)
                    Text("CUSTOM VIBRATION")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(1)
                    Spacer()
                    Image(systemName: showCustom ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)

            if showCustom {
                VStack(spacing: 16) {
                    // Intensity slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Intensity")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(customIntensity))%")
                                .font(.caption.monospaced())
                                .foregroundColor(intensityColor(Int(customIntensity)))
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                            Slider(value: $customIntensity, in: 1...100, step: 1)
                                .tint(intensityColor(Int(customIntensity)))
                            Image(systemName: "waveform.path.ecg.rectangle.fill")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                        }
                    }

                    // Pattern picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pattern")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)

                        HStack(spacing: 0) {
                            patternButton(.double, label: "Double")
                            patternButton(.rise, label: "Rise")
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Duration slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Duration")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(customDuration))s")
                                .font(.caption.monospaced())
                                .foregroundColor(Theme.textSecondary)
                        }

                        HStack(spacing: 8) {
                            Text("1s")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                            Slider(value: $customDuration, in: 1...60, step: 1)
                                .tint(Theme.cooling)
                            Text("60s")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)
                        }
                    }

                    // Test button
                    Button {
                        Haptics.medium()
                        Task { await triggerCustom() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Test Vibration")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }

    private func patternButton(_ pattern: VibrationPattern, label: String) -> some View {
        let isSelected = customPattern == pattern
        return Button {
            Haptics.tap()
            customPattern = pattern
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(isSelected ? Theme.cooling : Theme.cardElevated)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stop Button

    private var stopButton: some View {
        Button {
            Haptics.heavy()
            Task { await stopAllVibration() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 16))
                Text("Stop All Vibration")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(isVibrating ? Theme.error : Theme.error.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.3), value: isVibrating)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func triggerPreset(_ preset: VibrationPreset) async {
        if activePresetID == preset.id {
            await stopAllVibration()
            return
        }

        errorMessage = nil
        activePresetID = preset.id
        isVibrating = true

        do {
            var triggeredSides: [Side] = []
            for side in selectedSide.sides {
                let job = AlarmJob(
                    side: side,
                    vibrationIntensity: preset.intensity,
                    vibrationPattern: preset.pattern,
                    duration: preset.duration,
                    force: true
                )
                do {
                    try await api.triggerAlarm(job)
                    triggeredSides.append(side)
                } catch {
                    // Rollback: clear any sides that were already triggered
                    for triggered in triggeredSides {
                        try? await api.clearAlarm(side: triggered)
                    }
                    throw error
                }
            }

            // Auto-dismiss active state after duration
            let duration = preset.duration
            let presetID = preset.id
            Task {
                try? await Task.sleep(for: .seconds(duration))
                if activePresetID == presetID {
                    activePresetID = nil
                    isVibrating = false
                }
            }
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
            activePresetID = nil
            isVibrating = false
        }
    }

    private func triggerCustom() async {
        errorMessage = nil
        activePresetID = nil
        isVibrating = true

        do {
            var triggeredSides: [Side] = []
            for side in selectedSide.sides {
                let job = AlarmJob(
                    side: side,
                    vibrationIntensity: Int(customIntensity),
                    vibrationPattern: customPattern,
                    duration: Int(customDuration),
                    force: true
                )
                do {
                    try await api.triggerAlarm(job)
                    triggeredSides.append(side)
                } catch {
                    // Rollback: clear any sides that were already triggered
                    for triggered in triggeredSides {
                        try? await api.clearAlarm(side: triggered)
                    }
                    throw error
                }
            }

            let dur = Int(customDuration)
            Task {
                try? await Task.sleep(for: .seconds(dur))
                isVibrating = false
            }
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
            isVibrating = false
        }
    }

    private func stopAllVibration() async {
        errorMessage = nil
        var errors: [String] = []
        for side in [Side.left, .right] {
            do {
                try await api.clearAlarm(side: side)
            } catch {
                errors.append("\(side): \(error.localizedDescription)")
            }
        }
        if !errors.isEmpty {
            errorMessage = "Stop failed: \(errors.joined(separator: ", "))"
        }
        activePresetID = nil
        isVibrating = false
    }
}
