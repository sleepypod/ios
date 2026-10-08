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

    /// Big-number text: "76°" (°F), "24°" (°C) or the signed offset from 80°F in relative mode.
    static func valueText(_ tempF: Int, format: TemperatureFormat) -> String {
        switch format {
        case .fahrenheit: "\(tempF)°"
        case .celsius: "\(Int(tempFToC(tempF).rounded()))°"
        case .relative: offsetDisplay(tempF - baseTempF)
        }
    }

    /// Status word for a target against the bed temperature.
    static func stateWord(target: Int, bed: Int, isOn: Bool) -> String {
        !isOn ? "OFF" : target < bed ? "COOLING" : target > bed ? "WARMING" : "HOLDING"
    }

    static func offsetDisplay(_ offset: Int) -> String {
        if offset > 0 { return "+\(offset)" }
        if offset < 0 { return "−\(abs(offset))" }
        return "0"
    }
}

// MARK: - Temperature Colors

enum TempColor {
    static func forDelta(target: Int, current: Int) -> Color {
        target < current ? Theme.cool : target > current ? Theme.warm : Theme.neutral
    }

    static func forOffset(_ offset: Int) -> Color {
        forDelta(target: offset, current: 0)
    }

    /// Scheduled set points compare against the pod's 80°F neutral with a ±2° holding band,
    /// matching the source curve (76° cool, 78° neutral, 84° warm).
    static func forScheduled(_ tempF: Int) -> Color {
        let delta = tempF - TemperatureConversion.baseTempF
        return delta < -2 ? Theme.cool : delta > 2 ? Theme.warm : Theme.neutral
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
    static let background = Color("background")
    static let card = Color("card")
    static let active = Color("active")
    static let border1 = Color("border1")
    static let border2 = Color("border2")
    static let text1 = Color("text1")
    static let text2 = Color("text2")
    static let text3 = Color("text3")
    static let icon = Color("icon")
    static let cool = Color("cool")
    static let warm = Color("warm")
    static let neutral = Color("neutral")
    static let green = Color("green")
    static let amber = Color("amber")
    static let red = Color("red")
    static let violet = Color("violet")
    static let indigo = Color("indigo")
    static let track = Color("track")

    static let cardBorder = border1
    static let cardElevated = active
    static let warming = warm
    static let cooling = cool
    static let accent = cool
    static let healthy = green
    static let error = red
    static let purple = violet
    static let textSecondary = text2
    static let textTertiary = text3
    static let textMuted = text3
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
