import SwiftUI

struct WaterLevelSheet: View {
    let currentLevel: String

    @Environment(\.dismiss) private var dismiss
    @State private var isPriming = false
    @State private var primeResult: String?

    private var isLow: Bool {
        let low = currentLevel.lowercased()
        return low == "false" || low == "low" || low == "empty"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status icon
                    Image(systemName: isLow ? "drop.triangle.fill" : "drop.fill")
                        .font(.system(size: 48))
                        .foregroundColor(isLow ? Theme.amber : Theme.healthy)
                        .padding(.top, 16)

                    // Status text
                    VStack(spacing: 6) {
                        Text(isLow ? "Water Level Low" : "Water Level OK")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                        Text(isLow
                             ? "Your Sleepypod needs water. Low water can reduce heating/cooling performance and damage the pump."
                             : "Water level is good. The pod has enough water for normal operation.")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Refilling Water")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)

                        instructionRow(step: "1", text: "Unplug the pod from power")
                        instructionRow(step: "2", text: "Open the water reservoir cap on the back of the hub")
                        instructionRow(step: "3", text: "Fill with distilled water until the reservoir is full")
                        instructionRow(step: "4", text: "Close the cap securely")
                        instructionRow(step: "5", text: "Plug the pod back in and run Prime to circulate water")
                    }
                    .padding(16)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)

                    // Prime button
                    VStack(spacing: 12) {
                        Button {
                            Haptics.medium()
                            isPriming = true
                            Task {
                                do {
                                    let api = APIBackend.current.createClient()
                                    try await api.reboot() // startPriming is the current workaround
                                    primeResult = "Priming started — water is being circulated through the system"
                                } catch {
                                    primeResult = "Failed to start priming"
                                }
                                isPriming = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isPriming {
                                    ProgressView().tint(.white).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text(isPriming ? "Priming…" : "Start Prime")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(isPriming)
                        .padding(.horizontal, 16)

                        if let result = primeResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("Failed") ? Theme.error : Theme.healthy)
                                .padding(.horizontal, 16)
                        }

                        Text("Priming circulates water through the tubing to remove air bubbles. Takes 2-3 minutes.")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Theme.background)
            .navigationTitle("Water Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private func instructionRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundColor(Theme.accent)
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.15))
                .clipShape(Circle())

            Text(text)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }
}
