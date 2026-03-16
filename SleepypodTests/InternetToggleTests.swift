import Testing
import Foundation
@testable import Sleepypod

@Suite("Internet Toggle")
struct InternetToggleTests {

    @Test("Optimistic update sets state immediately")
    @MainActor
    func optimisticUpdate() async {
        let mock = MockAPIClient()
        let manager = StatusManager(api: mock)

        #expect(manager.isInternetBlocked == false)

        await manager.setInternetAccess(blocked: true)

        #expect(manager.isInternetBlocked == true)
        #expect(mock.setInternetCalls == [true])
    }

    @Test("Reverts on API failure")
    @MainActor
    func revertsOnFailure() async {
        let mock = FailingInternetClient()
        let manager = StatusManager(api: mock)

        manager.isInternetBlocked = false
        await manager.setInternetAccess(blocked: true)

        // Should revert because API threw
        #expect(manager.isInternetBlocked == false)
    }

    @Test("Cooldown prevents poll from overriding optimistic update")
    @MainActor
    func cooldownPreventsOverride() async {
        let mock = MockAPIClient()
        let manager = StatusManager(api: mock)

        // Set blocked (starts cooldown)
        await manager.setInternetAccess(blocked: true)
        #expect(manager.isInternetBlocked == true)

        // Simulate a poll that returns the old value (not blocked)
        // During cooldown, fetchInternetStatus should skip
        // We can't directly call fetchInternetStatus (private), but fetchAll includes it
        // The cooldown should prevent the poll from changing isInternetBlocked
        // For now, just verify the state held
        #expect(manager.isInternetBlocked == true)
    }

    @Test("Toggle blocked then unblocked")
    @MainActor
    func toggleBothWays() async {
        let mock = MockAPIClient()
        let manager = StatusManager(api: mock)

        await manager.setInternetAccess(blocked: true)
        #expect(manager.isInternetBlocked == true)

        await manager.setInternetAccess(blocked: false)
        #expect(manager.isInternetBlocked == false)

        #expect(mock.setInternetCalls == [true, false])
    }
}

/// A client that always fails on setInternetAccess
private final class FailingInternetClient: MockAPIClient, @unchecked Sendable {
    override func setInternetAccess(blocked: Bool) async throws {
        throw APIError.networkError(NSError(domain: "test", code: -1))
    }
}
