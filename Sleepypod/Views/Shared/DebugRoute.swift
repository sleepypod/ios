import Foundation

/// DEBUG-only deep link for design QA: `-uiRoute schedule|sleep|week|month|watch|settings|allsettings|onboard1|onboard2|onboard3`.
enum DebugRoute {
    static var current: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "uiRoute")
        #else
        nil
        #endif
    }
}
