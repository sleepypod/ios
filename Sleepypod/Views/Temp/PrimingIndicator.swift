import SwiftUI

/// Compact priming status indicator for the nav bar.
struct PrimingIndicator: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "drop.fill")
                .font(.system(size: 12))
                .foregroundColor(Theme.accent)
                .scaleEffect(isPulsing ? 1.2 : 0.9)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)

            Text("Priming")
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.accent)
        }
        .onAppear { isPulsing = true }
    }
}
