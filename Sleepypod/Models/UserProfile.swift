import Foundation
import Observation

@MainActor
@Observable
final class UserProfile {
    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: "userName") }
    }
    var defaultSide: Side {
        didSet { UserDefaults.standard.set(defaultSide.rawValue, forKey: "userDefaultSide") }
    }

    init() {
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
