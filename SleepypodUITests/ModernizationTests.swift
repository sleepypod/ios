import XCTest

@MainActor
final class ModernizationTests: XCTestCase {
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testThreeTabsAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-apiBackend", "demo", "-onboardingComplete", "YES", "-appearance", "Light", "-healthSyncEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Decrease temperature"].waitForExistence(timeout: 15))
        capture("Temp-light")
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["Schedule active"].waitForExistence(timeout: 10))
        capture("Schedule-light")
        app.tabBars.buttons["Sleep"].tap()
        XCTAssertTrue(app.buttons["Week"].waitForExistence(timeout: 10))
        capture("Sleep-light")
        app.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Stage model"].waitForExistence(timeout: 5))
        capture("Week-light")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Prime"].waitForExistence(timeout: 5))
        capture("Settings-sheet-light")
        app.buttons["Prime"].tap()
        XCTAssertTrue(app.buttons["Start priming"].waitForExistence(timeout: 3))
        app.buttons["Start priming"].tap()
        app.buttons["All settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.navigationBars["Settings"].frame.minY, 160)
        capture("Settings-top-light")
        for _ in 0..<6 where !app.staticTexts["Appearance"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        capture("Settings-list-light")
    }

    func testLinkedTemperatureControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-apiBackend", "demo", "-onboardingComplete", "YES", "-appearance", "Dark", "-healthSyncEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Decrease temperature"].waitForExistence(timeout: 10))
        let both = app.buttons["Both"]
        both.tap()
        app.buttons["Decrease temperature"].tap()
        let dial = app.descendants(matching: .any).matching(identifier: "Target temperature").firstMatch
        let linkedValue = dial.value as? String
        XCTAssertTrue(linkedValue?.contains("71°") == true)
        app.buttons["Right"].tap()
        XCTAssertTrue((dial.value as? String)?.contains("71°") == true)
        app.buttons["Turn off"].tap()
        XCTAssertTrue(app.buttons["Turn on"].exists)
        capture("Linked-controls-dark")
    }

    func testDemoOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-apiBackend", "sleepypod-core", "-podIPAddress", "", "-onboardingComplete", "NO", "-appearance", "Dark", "-healthSyncEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Explore demo"].waitForExistence(timeout: 10))
        capture("Find-pod-dark")
        app.buttons["Explore demo"].tap()
        XCTAssertTrue(app.staticTexts["Who sleeps where?"].waitForExistence(timeout: 10))
        capture("Choose-sides-dark")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 10))
        capture("Health-onboarding-dark")
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.tabBars.buttons["Temp"].waitForExistence(timeout: 5))
        capture("Temp-dark")
    }
}
