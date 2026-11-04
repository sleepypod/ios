import Foundation

/// DEBUG-only deep link for design QA: `-uiRoute schedule|sleep|week|weektrend|month|watch|stages|settings|allsettings|health|watchmotion|onboard1|onboard2`.
enum DebugRoute {
    static var current: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "uiRoute")
        #else
        nil
        #endif
    }

    /// DEBUG-only `-trainStageModel logistic|forest`: starts a personal model training run when the Stage models
    /// screen opens, so a device run can be driven from the command line.
    static var trainStageModel: StageModelKind? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "trainStageModel").flatMap(StageModelKind.init)
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
