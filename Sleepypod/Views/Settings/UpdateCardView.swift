import SwiftUI

struct UpdateCardView: View {
    @Environment(UpdateChecker.self) private var updateChecker
    @Environment(DeviceManager.self) private var deviceManager

    private var runningVersion: String {
        deviceManager.deviceStatus?.freeSleep.version ?? "—"
    }

    private var runningBranch: String {
        updateChecker.trackingBranch
    }

    var body: some View {
        if updateChecker.updateAvailable, let latest = updateChecker.latestVersion {
            updateAvailableCard(latest: latest)
        } else {
            upToDateCard
        }
    }

    // MARK: - Update Available

    private func updateAvailableCard(latest: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(Color(hex: "ffd700"))
                    Text("Update Available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.healthy)
                }
                Spacer()
                Text("NEW")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.error)
                    .clipShape(Capsule())
            }

            // Version transition
            HStack(spacing: 8) {
                versionTag("v\(runningVersion)", color: Theme.textSecondary, bg: Color(hex: "2a2a3a"))
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                versionTag("v\(latest)", color: Theme.healthy, bg: Theme.healthy.opacity(0.15))
            }

            // Release notes
            if let notes = updateChecker.latestReleaseNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                        Text("WHAT'S NEW")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Theme.textSecondary)
                            .tracking(0.5)
                    }

                    Text(notes.prefix(300))
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(6)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.healthy.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Up to Date

    private var upToDateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.healthy)
                Text("Software Up to Date")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
            }

            HStack(spacing: 8) {
                versionTag("v\(runningVersion)", color: Theme.healthy, bg: Theme.healthy.opacity(0.15))
                Text("on")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                versionTag(runningBranch, color: Theme.textSecondary, bg: Color(hex: "2a2a3a"))
            }

            // Check button
            Button {
                Haptics.light()
                Task { await updateChecker.checkForUpdate() }
            } label: {
                HStack(spacing: 6) {
                    if updateChecker.isChecking {
                        ProgressView()
                            .tint(Theme.accent)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(updateChecker.isChecking ? "Checking…" : "Check for Updates")
                }
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(updateChecker.isChecking)

            if let lastChecked = updateChecker.lastChecked {
                Text("Last checked: \(lastChecked, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
            }
        }
        .cardStyle()
    }

    private func versionTag(_ text: String, color: Color, bg: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
