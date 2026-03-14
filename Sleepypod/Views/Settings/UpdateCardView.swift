import SwiftUI

struct UpdateCardView: View {
    let freeSleep: FreeSleepInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.healthy)
                Text("Software Up to Date")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
            }

            // Version info
            HStack(spacing: 8) {
                versionTag(freeSleep.version)
                Text("on")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                branchTag(freeSleep.branch)
            }

            // Check button
            Button {
                // Future: check for updates
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Check for Updates")
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
        }
        .cardStyle()
    }

    private func versionTag(_ version: String) -> some View {
        Text("v\(version)")
            .font(.caption.weight(.medium))
            .foregroundColor(Theme.healthy)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.healthy.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func branchTag(_ branch: String) -> some View {
        Text(branch)
            .font(.caption)
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: "2a2a3a"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
