import OSLog

/// Centralized loggers for the app. Logs persist on device and can be pulled via:
///   log collect --device --start "2026-03-15" --output sleepypod.logarchive
///   log show sleepypod.logarchive --predicate 'subsystem == "com.sleepypod.ios"'
enum Log {
    static let network = Logger(subsystem: "com.sleepypod.ios", category: "network")
    static let discovery = Logger(subsystem: "com.sleepypod.ios", category: "discovery")
    static let device = Logger(subsystem: "com.sleepypod.ios", category: "device")
    static let general = Logger(subsystem: "com.sleepypod.ios", category: "general")
}
