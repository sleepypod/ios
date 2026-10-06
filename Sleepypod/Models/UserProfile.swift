import SwiftUI
import Observation

@MainActor
@Observable
final class UserProfile {
    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System", dark = "Dark", light = "Light"
        var id: String { rawValue }
        var colorScheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
    }
    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    var developer: Bool {
        didSet { UserDefaults.standard.set(developer, forKey: "developerMode") }
    }
    var onboardingComplete: Bool {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: "onboardingComplete") }
    }
    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: "userName") }
    }
    var defaultSide: Side {
        didSet { UserDefaults.standard.set(defaultSide.rawValue, forKey: "userDefaultSide") }
    }

    init() {
        appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "System") ?? .system
        developer = UserDefaults.standard.bool(forKey: "developerMode")
        onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        self.name = UserDefaults.standard.string(forKey: "userName") ?? ""
        let sideRaw = UserDefaults.standard.string(forKey: "userDefaultSide") ?? "left"
        self.defaultSide = Side(rawValue: sideRaw) ?? .left
    }

    var displayName: String {
        name.isEmpty ? defaultSide.displayName : name
    }

    var initial: String {
        if name.isEmpty { return defaultSide.initial }
        return String(name.prefix(1)).uppercased()
    }
}
