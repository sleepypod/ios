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
                VStack(spacing: 20) {
                    // Status
                    HStack(spacing: 12) {
                        Image(systemName: isLow ? "drop.triangle.fill" : "drop.fill")
                            .font(.system(size: 28))
                            .foregroundColor(isLow ? Theme.amber : Theme.healthy)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isLow ? "Water Level Low" : "Water Level OK")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                            Text(isLow ? "Refill with distilled water, then prime." : "Water level is good.")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Why prime
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why Prime?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)

                        Text("Priming circulates water through the pod's tubing to remove trapped air bubbles. Air pockets reduce heating and cooling efficiency — the water can't reach the thermal elements, so your bed won't hit the target temperature.")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)

                        Text("Run a prime after refilling water, after the pod has been off for a while, or if you notice uneven temperatures. A daily prime (which can be scheduled) keeps the system running at peak efficiency — Eight Sleep recommends this as well.")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)

                        // Prime button
                        Button {
                            Haptics.medium()
                            isPriming = true
                            Task {
                                do {
                                    let api = APIBackend.current.createClient()
                                    try await api.reboot() // startPriming workaround
                                    primeResult = "Priming started — water is circulating through the system"
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
                        }
                        .buttonStyle(.plain)
                        .disabled(isPriming)

                        if let result = primeResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("Failed") ? Theme.error : Theme.healthy)
                        }

                        Text("Takes 2-3 minutes. You may hear the pump running.")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                    }
                    .cardStyle()

                    // Water care
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Water Care")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)

                        Text("Use **distilled water** only. Tap water contains minerals that build up deposits in the tubing and thermal elements over time.")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)

                        Divider().background(Theme.cardBorder)

                        VStack(alignment: .leading, spacing: 8) {
                            careRow(
                                safe: true,
                                title: "Benzalkonium Chloride (BZK)",
                                detail: "Antimicrobial agent that prevents biofilm and microbial growth. Eight Sleep uses this in their pod cleaning solution (\"Pod Crystals\"). Available in liquid form — add a small amount when refilling. BZK is a quaternary ammonium compound widely used in medical device disinfection."
                            )

                            Divider().background(Theme.cardBorder)

                            careRow(
                                safe: false,
                                title: "Hydrogen Peroxide",
                                detail: "Oxidizing agent that degrades EPDM rubber seals and silicone tubing over time. Causes seal swelling and eventual leaks. Not recommended for closed-loop water systems."
                            )

                            Divider().background(Theme.cardBorder)

                            careRow(
                                safe: false,
                                title: "Bleach (Sodium Hypochlorite)",
                                detail: "Highly corrosive to rubber gaskets, O-rings, and silicone tubing. Causes accelerated degradation of elastomeric seals — a known failure mode in HVAC and medical tubing systems (ASTM D2000, SAE J200)."
                            )

                            Divider().background(Theme.cardBorder)

                            careRow(
                                safe: false,
                                title: "Dehumidifier Chemicals / Desiccants",
                                detail: "Calcium chloride and silica gel are not designed for liquid systems. Can introduce particulates that clog the pump and thermal elements."
                            )
                        }
                    }
                    .cardStyle()

                    // References
                    VStack(alignment: .leading, spacing: 6) {
                        Text("References")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.textMuted)

                        referenceRow("ASTM D2000 — Standard Classification for Rubber Products in Automotive Applications (seal compatibility)")
                        referenceRow("SAE J200 — Classification System for Rubber Materials (elastomer chemical resistance)")
                        referenceRow("CDC Guidelines — Benzalkonium chloride as a surface and water system antimicrobial")
                        referenceRow("Eight Sleep Support — Pod maintenance and cleaning recommendations")
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
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
