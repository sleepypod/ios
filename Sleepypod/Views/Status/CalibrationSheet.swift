import SwiftUI

struct CalibrationSheet: View {
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSide: Side?
    @State private var isCalibrating = false
    @State private var result: String?

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

                Spacer()

                // Side selection buttons
                if !isCalibrating && result == nil {
                    VStack(spacing: 12) {
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
                    VStack(spacing: 8) {
                        ProgressView().tint(Theme.cyan)
                        Text("Calibrating \(selectedSide?.displayName ?? "both sides")…")
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
        Task {
            let api = APIBackend.current.createClient()
            for sensor in ["piezo", "temperature", "capacitance"] {
                _ = try? await api.triggerCalibration(side: side, sensorType: sensor)
            }
            result = "Calibration queued for \(side.displayName) side"
            isCalibrating = false
            onComplete()
        }
    }

    private func triggerFull() {
        selectedSide = nil
        isCalibrating = true
        Task {
            let api = APIBackend.current.createClient()
            _ = try? await api.triggerFullCalibration()
            result = "Full calibration queued for all sensors on both sides"
            isCalibrating = false
            onComplete()
        }
    }
}
