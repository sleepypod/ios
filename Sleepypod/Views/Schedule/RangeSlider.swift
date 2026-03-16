import SwiftUI

/// A dual-thumb range slider for selecting min/max values.
struct RangeSlider: View {
    @Binding var low: Double
    @Binding var high: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var trackHeight: CGFloat = 6
    var thumbSize: CGFloat = 24

    private var span: Double { range.upperBound - range.lowerBound }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - thumbSize

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color(hex: "222222"))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                // Active range fill
                let lowX = ((low - range.lowerBound) / span) * width
                let highX = ((high - range.lowerBound) / span) * width

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.cooling, Theme.textSecondary, Theme.warming],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: highX - lowX, height: trackHeight)
                    .offset(x: lowX + thumbSize / 2)

                // Low thumb
                thumb(color: Theme.cooling)
                    .offset(x: lowX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newVal = range.lowerBound + (value.location.x / width) * span
                                let stepped = (newVal / step).rounded() * step
                                low = max(range.lowerBound, min(stepped, high - step))
                                Haptics.light()
                            }
                    )

                // High thumb
                thumb(color: Theme.warming)
                    .offset(x: highX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newVal = range.lowerBound + (value.location.x / width) * span
                                let stepped = (newVal / step).rounded() * step
                                high = min(range.upperBound, max(stepped, low + step))
                                Haptics.light()
                            }
                    )
            }
        }
        .frame(height: thumbSize)
    }

    private func thumb(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: color.opacity(0.4), radius: 4)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
    }
}
