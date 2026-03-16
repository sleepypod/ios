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
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Status — single line
                        HStack(spacing: 10) {
                            Image(systemName: isLow ? "drop.triangle.fill" : "drop.fill")
                                .font(.system(size: 20))
                                .foregroundColor(isLow ? Theme.amber : Theme.healthy)
                            Text(isLow ? "Water level is low — refill and prime" : "Water level is good")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Priming
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Priming")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)

                            Text("Priming circulates water through the pod's tubing to remove trapped air bubbles. Air pockets reduce heating and cooling efficiency — the water can't reach the thermal elements, so your bed won't hit the target temperature.")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)

                            Text("Run a prime after refilling water, after the pod has been off for a while, or if you notice uneven temperatures. A daily prime keeps the system running at peak efficiency — Eight Sleep recommends this as well.")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)

                            Text("Takes 2-3 minutes. You may hear the pump running.")
                                .font(.caption2)
                                .foregroundColor(Theme.textMuted)

                            if let result = primeResult {
                                HStack(spacing: 6) {
                                    Image(systemName: result.contains("Failed") ? "xmark.circle.fill" : "checkmark.circle.fill")
                                        .font(.caption)
                                    Text(result)
                                        .font(.caption)
                                }
                                .foregroundColor(result.contains("Failed") ? Theme.error : Theme.healthy)
                            }
                        }
                        .cardStyle()

                        // Water care
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Water Care")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)

                            VStack(alignment: .leading, spacing: 8) {
                                careRow(
                                    safe: true,
                                    title: "Benzalkonium Chloride (BZK)",
                                    detail: "Antimicrobial that prevents biofilm and microbial growth in closed-loop water systems. Eight Sleep uses this in their cleaning solution (\"Pod Crystals\"). Available in liquid form — add a small amount when refilling."
                                )

                                Divider().background(Theme.cardBorder)

                                careRow(
                                    safe: false,
                                    title: "Hydrogen Peroxide",
                                    detail: "Oxidizing agent that degrades EPDM rubber seals and silicone tubing over time. Causes seal swelling and eventual leaks."
                                )

                                Divider().background(Theme.cardBorder)

                                careRow(
                                    safe: false,
                                    title: "Bleach (Sodium Hypochlorite)",
                                    detail: "Highly corrosive to rubber gaskets, O-rings, and silicone tubing. Causes accelerated degradation of elastomeric seals (ASTM D2000, SAE J200)."
                                )

                                Divider().background(Theme.cardBorder)

                                careRow(
                                    safe: false,
                                    title: "Dehumidifier Chemicals",
                                    detail: "Calcium chloride and silica gel introduce particulates that clog the pump and thermal elements."
                                )
                            }
                        }
                        .cardStyle()

                        // References
                        VStack(alignment: .leading, spacing: 6) {
                            Text("References")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textMuted)

                            referenceRow("ASTM D2000 — Rubber Products Classification (seal compatibility)")
                            referenceRow("SAE J200 — Rubber Materials Classification (chemical resistance)")
                            referenceRow("CDC — Benzalkonium chloride as water system antimicrobial")
                            referenceRow("Eight Sleep — Pod maintenance recommendations")
                        }
                        .padding(.horizontal, 16)

                        // Bottom padding for floating button
                        Spacer().frame(height: 80)
                    }
                    .padding(.bottom, 20)
                }

                // Floating prime button
                Button {
                    Haptics.medium()
                    isPriming = true
                    Task {
                        do {
                            let api = APIBackend.current.createClient()
                            try await api.reboot()
                            primeResult = "Priming started — water is circulating"
                            Haptics.heavy()
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
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(isPriming)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.background)
            .navigationTitle("Water & Priming")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private func careRow(safe: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: safe ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(safe ? Theme.healthy : Theme.error)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    private func referenceRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.caption2)
                .foregroundColor(Theme.textMuted)
            Text(text)
                .font(.system(size: 9))
                .foregroundColor(Theme.textMuted)
        }
    }
}
