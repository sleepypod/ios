import SwiftUI

enum TemperatureConversion {
    static let baseTempF = 80
    static let minOffset = -10
    static let maxOffset = 10
    static let minTempF = 55
    static let maxTempF = 110

    static func tempFToOffset(_ tempF: Int) -> Int {
        (tempF - baseTempF) / 2
    }

    static func offsetToTempF(_ offset: Int) -> Int {
        baseTempF + offset * 2
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
    static func forOffset(_ offset: Int) -> Color {
        if offset < 0 { return Theme.cooling }
        if offset > 0 { return Theme.warming }
        return Theme.textSecondary
    }

    static func glowForOffset(_ offset: Int) -> Color {
        if offset < 0 { return Theme.cooling.opacity(0.6) }
        if offset > 0 { return Theme.warming.opacity(0.6) }
        return Color.gray.opacity(0.3)
    }
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
