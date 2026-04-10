import OSLog

/// Centralized loggers for the app. Logs persist on device and can be pulled via:
///   log collect --device --start "2026-03-15" --output sleepypod.logarchive
///   log show sleepypod.logarchive --predicate 'subsystem == "com.jonathanng.ios.sleepypod"'
enum Log {
    static let network = Logger(subsystem: "com.jonathanng.ios.sleepypod", category: "network")
    static let discovery = Logger(subsystem: "com.jonathanng.ios.sleepypod", category: "discovery")
    static let device = Logger(subsystem: "com.jonathanng.ios.sleepypod", category: "device")
    static let general = Logger(subsystem: "com.jonathanng.ios.sleepypod", category: "general")
    static let sensor = Logger(subsystem: "com.jonathanng.ios.sleepypod", category: "sensor")
}
