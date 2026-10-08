import XCTest

final class FirstBootTests: XCTestCase {
    @MainActor
    func testFreshInstallConnectsAndRelaunches() throws {
        guard ProcessInfo.processInfo.environment["POD_UI_TEST"] == "1" else {
            throw XCTSkip("Run on a fresh simulator with TEST_RUNNER_POD_UI_TEST=1 and a reachable local pod")
        }
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5), "A fresh install must show welcome")
        addUIInterruptionMonitor(withDescription: "Local network access") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        connect.tap()
        let controls = app.descendants(matching: .any)["podSideSelector"].firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 10), "Discovery should reach usable controls promptly")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowNotifications = springboard.alerts.buttons["Allow"]
        if allowNotifications.waitForExistence(timeout: 2) { allowNotifications.tap() }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "First connection"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(controls.waitForExistence(timeout: 5), "Saved-address launch should reconnect promptly")
        XCTAssertFalse(app.buttons["Connect"].exists)
    }
}
