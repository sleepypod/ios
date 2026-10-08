import SwiftUI

enum TemperatureConversion {
    static let baseTempF = 80
    static let minOffset = -20
    static let maxOffset = 20
    static let minTempF = 55
    static let maxTempF = 110

    static func tempFToOffset(_ tempF: Int) -> Int {
        tempF - baseTempF
    }

    static func offsetToTempF(_ offset: Int) -> Int {
        baseTempF + offset
    }

    static func tempFToC(_ tempF: Int) -> Double {
        Double(tempF - 32) * 5.0 / 9.0
    }

    static func tempCToF(_ tempC: Double) -> Int {
        Int(round(tempC * 9.0 / 5.0 + 32))
    }

    static func displayTemp(_ tempF: Int, format: TemperatureFormat) -> String {
        switch format {
        case .fahrenheit:
            return "\(tempF)°F"
        case .celsius:
            let c = tempFToC(tempF)
            return "\(Int(round(c)))°C"
        case .relative:
            let offset = tempFToOffset(tempF)
            return offsetDisplay(offset)
        }
    }

    static func offsetDisplay(_ offset: Int) -> String {
        if offset > 0 { return "+\(offset)" }
        if offset < 0 { return "\(offset)" }
        return "0"
    }
}

// MARK: - Temperature Colors

enum TempColor {
    // Deep blue → soft blue → neutral → soft orange → deep red
    private static let coldDeep = Color(hex: "2563eb")   // -10°F+
    private static let coldMid  = Color(hex: "4a90d9")   // -5°F
    private static let coldSoft = Color(hex: "7ab5e0")   // -2°F
    private static let neutral  = Color(hex: "9ca3af")   // 0°F
    private static let warmSoft = Color(hex: "e0976a")   // +2°F
    private static let warmMid  = Color(hex: "dc6646")   // +5°F
    private static let warmDeep = Color(hex: "dc2626")   // +10°F+

    /// Gradient color based on delta between target and current temp.
    /// Intensity scales with how far apart they are.
    static func forDelta(target: Int, current: Int) -> Color {
        let delta = target - current  // positive = warming, negative = cooling
        return colorForDelta(delta)
    }

    static func glowForDelta(target: Int, current: Int) -> Color {
        let delta = target - current
        let intensity = min(abs(Double(delta)) / 8.0, 1.0) * 0.8
        return colorForDelta(delta).opacity(max(intensity, 0.3))
    }

    /// Offset-based color for side selector (relative to 80°F base)
    static func forOffset(_ offset: Int) -> Color {
        colorForDelta(offset)
    }

    private static func colorForDelta(_ delta: Int) -> Color {
        switch delta {
        case ...(-8): return coldDeep
        case -7...(-5): return coldMid
        case -4...(-2): return coldSoft
        case -1...1: return neutral
        case 2...4: return warmSoft
        case 5...7: return warmMid
        default: return warmDeep
        }
    }
}

// MARK: - Temperature Ramp

/// One ramp colours every absolute temperature (dial, thermal bed) so the eye learns it once.
/// Ported from sleepypod-core's TEMP_RAMP: cool blue, the mattress cover's grey at the middle, warm amber.
enum TempRamp {
    static let stops: [(f: Double, r: Double, g: Double, b: Double)] = [
        (64, 60, 105, 165),
        (80.5, 78, 82, 92),
        (97, 180, 108, 60)
    ]

    /// 0...1 RGB, linear between the stops and clamped at the ends; no reading is the middle grey.
    static func rgb(_ f: Double?) -> (r: Double, g: Double, b: Double) {
        let mid = stops[1]
        guard let f, f.isFinite else { return (mid.r / 255, mid.g / 255, mid.b / 255) }
        let first = stops[0], last = stops[stops.count - 1]
        if f <= first.f { return (first.r / 255, first.g / 255, first.b / 255) }
        if f >= last.f { return (last.r / 255, last.g / 255, last.b / 255) }
        for i in 0..<(stops.count - 1) where f <= stops[i + 1].f {
            let a = stops[i], b = stops[i + 1]
            let t = (f - a.f) / (b.f - a.f)
            return ((a.r + (b.r - a.r) * t) / 255, (a.g + (b.g - a.g) * t) / 255, (a.b + (b.b - a.b) * t) / 255)
        }
        return (mid.r / 255, mid.g / 255, mid.b / 255)
    }

    static func color(_ f: Double?) -> Color {
        let c = rgb(f)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    static func color(_ f: Int) -> Color { color(Double(f)) }

    /// The ramp colour lifted toward white so numerals stay readable on the dark background.
    static func labelColor(_ f: Int) -> Color {
        let c = rgb(Double(f))
        let lift = 0.45
        return Color(red: c.r + (1 - c.r) * lift, green: c.g + (1 - c.g) * lift, blue: c.b + (1 - c.b) * lift)
    }

    static var minF: Double { stops[0].f }
    static var maxF: Double { stops[stops.count - 1].f }
}

// MARK: - Theme Colors

enum Theme {
    static let background = Color(hex: "0a0a0a")
    static let card = Color(hex: "141414")
    static let cardBorder = Color(hex: "333333")
    static let cardElevated = Color(hex: "1a1a1a")

    static let warming = Color(hex: "dc6646")
    static let cooling = Color(hex: "4a90d9")
    static let accent = Color(hex: "5cb8e0")
    static let healthy = Color(hex: "50c878")
    static let error = Color(hex: "e05050")
    static let amber = Color(hex: "d4a84a")
    static let purple = Color(hex: "a080d0")
    static let cyan = Color(hex: "4ecdc4")

    static let textSecondary = Color(hex: "888888")
    static let textTertiary = Color(hex: "666666")
    static let textMuted = Color(hex: "555555")
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Card Style Modifier

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
