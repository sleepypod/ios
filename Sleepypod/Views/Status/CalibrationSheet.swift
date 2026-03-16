import SwiftUI

struct CalibrationSheet: View {
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSide: Side?
    @State private var isCalibrating = false
    @State private var result: String?
    @State private var statusText: String?
    @State private var terminalLines: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "tuningfork")
                    .font(.system(size: 44))
                    .foregroundColor(Theme.cyan)
                    .padding(.top, 20)

                // Title
                Text("Sensor Calibration")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)

                // Explanation
                VStack(alignment: .leading, spacing: 12) {
                    explanationRow(
                        icon: "bed.double.fill",
                        text: "Bed must be **empty** — blankets and sheets are fine, but nobody on the mattress"
                    )
                    explanationRow(
                        icon: "timer",
                        text: "Needs a quiet 5-minute window in the last 6 hours. Takes ~7 seconds per sensor to process."
                    )
                    explanationRow(
                        icon: "arrow.triangle.2.circlepath",
                        text: "Runs automatically on startup and daily. Profiles expire after 48 hours."
                    )
                    explanationRow(
                        icon: "square.split.2x1",
                        text: "Each side calibrates independently — you can have someone on one side while calibrating the other"
                    )
                }
                .padding(.horizontal, 24)

                if let result {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(Theme.healthy)
                        .padding(.horizontal, 24)
                }

                // Terminal output
                if !terminalLines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(terminalLines.enumerated()), id: \.offset) { i, line in
                                    Text(line)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(terminalColor(line))
                                        .id(i)
                                }
                            }
                            .padding(10)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Color(hex: "0a0a0f"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                        .onChange(of: terminalLines.count) {
                            withAnimation { proxy.scrollTo(terminalLines.count - 1, anchor: .bottom) }
                        }
                    }
                }

                Spacer(minLength: 0)

                // Side selection buttons
                if !isCalibrating && result == nil {
                    VStack(spacing: 12) {
                        Text("Left and right are from the foot of the bed looking up")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)

                        HStack(spacing: 12) {
                            sideButton(.left)
                            sideButton(.right)
                        }

                        Button {
                            Haptics.medium()
                            triggerFull()
                        } label: {
                            Text("Calibrate Both Sides")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                } else if isCalibrating {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.cyan).scaleEffect(0.8)
                        Text("Calibrating…")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                }

                Button("Cancel") { dismiss() }
                    .font(.subheadline)
                    .foregroundColor(Theme.textMuted)
                    .padding(.bottom, 20)
            }
            .background(Theme.background)
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func explanationRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.cyan)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func sideButton(_ side: Side) -> some View {
        Button {
            Haptics.medium()
            triggerSide(side)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 16))
                Text("\(side.displayName) Side")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(Theme.cyan)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.cyan.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func triggerSide(_ side: Side) {
        selectedSide = side
        isCalibrating = true
        terminalLines = []
        Haptics.medium()
        log("Triggering \(side.displayName) side calibration…")
        Task {
            let api = APIBackend.current.createClient()
            for sensor in ["piezo", "temperature", "capacitance"] {
                log("  → \(sensor)")
                _ = try? await api.triggerCalibration(side: side, sensorType: sensor)
            }
            log("All sensors triggered. Polling for completion…")
            await pollUntilDone(sides: [side])
        }
    }

    private func triggerFull() {
        selectedSide = nil
        isCalibrating = true
        terminalLines = []
        Haptics.medium()
        log("Triggering full calibration (both sides, all sensors)…")
        Task {
            let api = APIBackend.current.createClient()
            _ = try? await api.triggerFullCalibration()
            log("Triggered. Polling for completion…")
            await pollUntilDone(sides: [.left, .right])
            onComplete()
        }
    }

    private func pollUntilDone(sides: [Side]) async {
        let api = APIBackend.current.createClient()

        try? await Task.sleep(for: .seconds(2))
        log("Polling calibration status…")

        for attempt in 1...20 {
            var pending = 0
            var summaryParts: [String] = []

            for side in sides {
                guard let cal = try? await api.getCalibrationStatus(side: side) else {
                    log("  \(side.displayName): waiting for response…")
                    pending += 1
                    continue
                }
                for sensor in cal.sensors {
                    let name = "\(side.displayName) \(sensorShortName(sensor.sensorType))"
                    switch sensor.status {
                    case "pending":
                        pending += 1
                        log("  \(name): pending")
                    case "running":
                        pending += 1
                        log("  \(name): running…")
                    case "completed":
                        let q = Int((sensor.qualityScore ?? 0) * 100)
                        log("  ✓ \(name): completed (\(q)% quality, \(sensor.samplesUsed ?? 0) samples)")
                        summaryParts.append("\(sensorShortName(sensor.sensorType)) \(q)%")
                    case "failed":
                        log("  ✗ \(name): failed — \(sensor.errorMessage ?? "unknown error")")
                        summaryParts.append("\(sensorShortName(sensor.sensorType)) failed")
                    default:
                        log("  \(name): \(sensor.status)")
                        summaryParts.append("\(sensorShortName(sensor.sensorType)) \(sensor.status)")
                    }
                }
            }

            if pending == 0 {
                let summary = summaryParts.joined(separator: " · ")
                log("")
                log("Done: \(summary.isEmpty ? "all complete" : summary)")
                result = summary.isEmpty ? "Calibration complete" : summary
                isCalibrating = false
                Haptics.heavy()
                try? await Task.sleep(for: .milliseconds(200))
                Haptics.heavy()
                return
            }

            log("  … \(pending) sensor(s) still processing (poll \(attempt)/20)")
            try? await Task.sleep(for: .seconds(3))
        }

        log("Timed out after 60 seconds")
        result = "Calibration timed out — check status page"
        isCalibrating = false
        Haptics.medium()
    }

    private func log(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        terminalLines.append("[\(time)] \(text)")
    }

    private func terminalColor(_ line: String) -> Color {
        if line.contains("✓") || line.contains("completed") || line.contains("done") { return Theme.healthy }
        if line.contains("✗") || line.contains("failed") || line.contains("error") { return Theme.error }
        if line.contains("pending") || line.contains("running") || line.contains("…") { return Theme.amber }
        return Theme.textSecondary
    }

    private func sensorShortName(_ type: String) -> String {
        switch type.lowercased() {
        case "piezo": "Piezo"
        case "temperature": "Temp"
        case "capacitance": "Cap"
        default: type
        }
    }
}
