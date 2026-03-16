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
                        text: "Lie down on your side of the pod and stay still"
                    )
                    explanationRow(
                        icon: "timer",
                        text: "Calibration takes about 5 minutes to collect baseline readings"
                    )
                    explanationRow(
                        icon: "heart.fill",
                        text: "**Piezo** measures your heartbeat vibrations through the mattress"
                    )
                    explanationRow(
                        icon: "thermometer.medium",
                        text: "**Temperature** maps your body heat pattern"
                    )
                    explanationRow(
                        icon: "hand.raised.fill",
                        text: "**Capacitance** detects your presence on the pad"
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
