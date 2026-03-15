import Foundation

enum APIBackend: String, CaseIterable, Sendable {
    case freeSleep = "free-sleep"
    case sleepypodCore = "sleepypod-core"

    var displayName: String {
        switch self {
        case .freeSleep: "Free Sleep"
        case .sleepypodCore: "SleepyPod Core"
        }
    }

    var description: String {
        switch self {
        case .freeSleep: "Original free-sleep server (Express/REST)"
        case .sleepypodCore: "SleepyPod Core rewrite (Next.js/tRPC)"
        }
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
                return .freeSleep
            }
            return backend
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
