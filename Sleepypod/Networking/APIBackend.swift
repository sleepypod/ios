import Foundation

enum APIBackend: String, CaseIterable, Sendable {
    case freeSleep = "free-sleep"
    case sleepypodCore = "sleepypod-core"

    var displayName: String {
        switch self {
        case .freeSleep: "Free Sleep (Legacy)"
        case .sleepypodCore: "Sleepypod"
        }
    }

    var description: String {
        switch self {
        case .freeSleep: "Legacy server — some features may be incomplete or unsupported"
        case .sleepypodCore: "Built for reliability with full feature support"
        }
    }

    var isRecommended: Bool {
        self == .sleepypodCore
    }

    func createClient() -> FreeSleepAPIProtocol {
        switch self {
        case .freeSleep:
            FreeSleepClient()
        case .sleepypodCore:
            SleepypodCoreClient()
        }
    }

    // MARK: - Persistence

    private static let key = "apiBackend"

    static var current: APIBackend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let backend = APIBackend(rawValue: raw) else {
                return .sleepypodCore
            }
            return backend
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
