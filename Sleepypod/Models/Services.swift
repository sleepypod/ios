import Foundation

struct BiometricsJobs: Codable, Sendable {
    var analyzeSleepLeft: StatusInfo
    var analyzeSleepRight: StatusInfo
    var installation: StatusInfo
    var stream: StatusInfo
    var calibrateLeft: StatusInfo
    var calibrateRight: StatusInfo
}

struct Biometrics: Codable, Sendable {
    var enabled: Bool
    var jobs: BiometricsJobs
}

struct SentryLogging: Codable, Sendable {
    var enabled: Bool
}

struct Services: Codable, Sendable {
    var biometrics: Biometrics
    var sentryLogging: SentryLogging
}
