import Testing
import Foundation
@testable import Sleepypod

@Suite("Health background sync")
struct HealthBackgroundSyncTests {

    @Test("The background task identifier is permitted in Info.plist")
    func taskIdentifierPermitted() throws {
        let ids = Bundle(for: SleepypodCoreClient.self).object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        #expect(ids?.contains(HealthSyncService.backgroundTaskID) == true)
        let modes = Bundle(for: SleepypodCoreClient.self).object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("fetch") == true)
    }

    @Test("Cancelled requests aren't recorded as failed nights")
    func cancellationIsNotFailure() {
        #expect(HealthSyncService.isCancellation(CancellationError()))
        #expect(HealthSyncService.isCancellation(URLError(.cancelled)))
        #expect(HealthSyncService.isCancellation(APIError.networkError(URLError(.cancelled))))
        #expect(!HealthSyncService.isCancellation(APIError.networkError(URLError(.cannotConnectToHost))))
        #expect(!HealthSyncService.isCancellation(APIError.invalidResponse(statusCode: 500)))
    }

    @Test("Only dropped or timed-out connections are retried")
    func transientErrors() {
        #expect(SleepypodCoreClient.isTransient(URLError(.networkConnectionLost)))
        #expect(SleepypodCoreClient.isTransient(URLError(.timedOut)))
        #expect(!SleepypodCoreClient.isTransient(URLError(.cancelled)))
        #expect(!SleepypodCoreClient.isTransient(URLError(.cannotFindHost)))
    }
}
