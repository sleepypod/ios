import SwiftUI

/// Branded loading view — a breathing pulse animation themed around sleep.
struct LoadingView: View {
    @State private var phase: CGFloat = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var textOpacity: Double = 0.4
    var message: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                // Outer glow rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.accent.opacity(0.08 - Double(i) * 0.02), lineWidth: 2)
                        .frame(width: 80 + CGFloat(i) * 30, height: 80 + CGFloat(i) * 30)
                        .scaleEffect(ringScale + CGFloat(i) * 0.05)
                }

                // Center icon
                Image("WelcomeLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .scaleEffect(ringScale)

                // Arc spinner
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(phase))
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .opacity(textOpacity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.6)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                ringScale = 1.0
                textOpacity = 0.8
            }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
    }
}
