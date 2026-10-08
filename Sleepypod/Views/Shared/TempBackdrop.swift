import SwiftUI

/// Hues shared with sleepypod-core's `src/lib/tempColors.ts` (tempHue / skyHue).
enum TempHue {
    /// Pod level 0 (82.5°F).
    static let neutralF = 82.5

    /// Blue when cool, violet around neutral, rose when warm — saturating 8°F either side.
    static func temperature(_ tempF: Double) -> Double {
        let t = max(-1, min(1, (tempF - neutralF) / 8))
        return (t < 0 ? 268 + t * 45 : 268 + t * 77).rounded()
    }

    /// Sky hue for minutes past midnight: indigo night, rose-amber dawn, pale sky by day, violet dusk.
    static func sky(minutes: Int) -> Double {
        let m = Double((minutes % 1440 + 1440) % 1440)
        let stops: [(Double, Double)] = [(0, 235), (300, 240), (390, 15), (480, 205), (1020, 205), (1140, 290), (1290, 235), (1440, 235)]
        for (index, stop) in stops.dropLast().enumerated() {
            let next = stops[index + 1]
            guard m >= stop.0 && m <= next.0 else { continue }
            var delta = next.1 - stop.1
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            return ((stop.1 + delta * (m - stop.0) / (next.0 - stop.0) + 360).truncatingRemainder(dividingBy: 360)).rounded()
        }
        return 235
    }

    /// Temperature-tinted text (`.sp-temp-ink`).
    static func ink(_ tempF: Int, scheme: ColorScheme) -> Color {
        let hue = temperature(Double(tempF))
        return scheme == .dark ? Color(hue: hue, saturation: 0.62, lightness: 0.74) : Color(hue: hue, saturation: 0.50, lightness: 0.42)
    }
}

extension Color {
    /// CSS-style HSL (hue in degrees, saturation/lightness 0–1).
    init(hue: Double, saturation: Double, lightness: Double, opacity: Double = 1) {
        let v = lightness + saturation * min(lightness, 1 - lightness)
        let s = v == 0 ? 0 : 2 * (1 - lightness / v)
        self.init(hue: (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360,
                  saturation: s, brightness: v, opacity: opacity)
    }
}

/// The stepper card's backdrop, as in sleepypod-core's TempBackdrop: a wash for the time of day across
/// the top and a glow rising from below tinted by the temperature. Powered off, both give way to a
/// flat dark gradient. Both layers ease when their inputs change.
struct TempBackdrop: View {
    let tempF: Int?
    let minutes: Int
    var off = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Theme.card
                sky
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.65)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(off ? 0 : 1)
                glow
                    .mask(EllipticalGradient(colors: [.black, .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: size.width * 1.8, height: size.height * 1.3)
                        .position(x: size.width * 0.5, y: size.height * 0.8))
                    .opacity(off || tempF == nil ? 0 : 1)
                LinearGradient(colors: scheme == .dark
                               ? [Color(red: 0x17 / 255, green: 0x18 / 255, blue: 0x1d / 255), Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x16 / 255)]
                               : [Color(red: 0xf3 / 255, green: 0xf3 / 255, blue: 0xf5 / 255), Color(red: 0xec / 255, green: 0xec / 255, blue: 0xef / 255)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(off ? 1 : 0)
            }
        }
        .opacity(reduceTransparency ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.7), value: tempF)
        .animation(.easeInOut(duration: 0.7), value: minutes)
        .animation(.easeInOut(duration: 0.7), value: off)
        .accessibilityHidden(true)
    }

    private var sky: Color {
        let hue = TempHue.sky(minutes: minutes)
        return scheme == .dark
            ? Color(hue: hue, saturation: 0.45, lightness: 0.32, opacity: 0.4)
            : Color(hue: hue, saturation: 0.70, lightness: 0.86, opacity: 0.55)
    }

    private var glow: Color {
        let hue = TempHue.temperature(Double(tempF ?? 82))
        return scheme == .dark
            ? Color(hue: hue, saturation: 0.55, lightness: 0.56, opacity: 0.5)
            : Color(hue: hue, saturation: 0.70, lightness: 0.72, opacity: 0.45)
    }
}
