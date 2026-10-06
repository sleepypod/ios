import Foundation

/// DEBUG-only deep link for design QA: `-uiRoute schedule|sleep|week|weektrend|month|watch|settings|allsettings|onboard1|onboard2|onboard3`.
enum DebugRoute {
    static var current: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "uiRoute")
        #else
        nil
        #endif
    }

    /// DEBUG-only `-marketingCapture YES`: skips the notification prompt and the DEMO badge so App Store captures show the plain UI.
    static var marketingCapture: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "marketingCapture")
        #else
        false
        #endif
    }
}
