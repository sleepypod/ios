import SwiftUI

// TODO: Version and changelog are hardcoded. Wire up to sleepypod-core repo releases.
struct UpdateCardView: View {
    let currentVersion: String
    let currentBranch: String

    private let fakeNewVersion = "2.2.0"
    private let changelog = [
        "Improved temperature control accuracy",
        "Fixed scheduling bug for recurring alarms",
        "Added new biometrics dashboard"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
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
                versionTag("v\(currentVersion)", color: Theme.textSecondary, bg: Color(hex: "2a2a3a"))
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                versionTag("v\(fakeNewVersion)", color: Theme.healthy, bg: Theme.healthy.opacity(0.15))
            }

            // Changelog
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                    Text("WHAT'S NEW")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(0.5)
                }

                ForEach(changelog, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(Theme.textMuted)
                        Text(item)
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }

            // Update button
            Button {
                Haptics.medium()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Update to v\(fakeNewVersion)")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.healthy)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
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
