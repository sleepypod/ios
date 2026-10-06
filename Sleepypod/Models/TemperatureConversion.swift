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
