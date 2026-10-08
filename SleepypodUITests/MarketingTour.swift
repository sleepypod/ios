import XCTest

/// Paced UI tours for App Store previews and marketing video. `Marketing/AppStore/capture.py --video`
/// records the simulator between the `MARKETING_MARK` lines printed here.
/// Skipped unless the runner sees `MARKETING_TOUR=1` (xcodebuild passes `TEST_RUNNER_MARKETING_TOUR=1`).
@MainActor
final class MarketingTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["MARKETING_TOUR"] == "1", "Run through Marketing/AppStore/capture.py --video")
        continueAfterFailure = false
    }

    func testClipTemperature() throws {
        launch(control: "dial")
        XCTAssertTrue(app.buttons["Decrease temperature"].waitForExistence(timeout: 15))
        begin()
        dragDial(from: 72, to: 79)
        pause(1.0)
        dragDial(from: 79, to: 66)
        pause(1.0)
        tap(app.buttons["Increase temperature"], hold: 1.2)
        tap(app.buttons["Both"], hold: 1.4)
        tap(app.buttons["Right"], hold: 1.0)
        tap(app.buttons["Decrease temperature"], hold: 1.2)
        tap(app.buttons["Left"], hold: 2.0)
        end()
    }

    func testClipNightAndDawn() throws {
        launch(control: "stepper")
        XCTAssertTrue(app.buttons["Night"].waitForExistence(timeout: 15))
        begin()
        pause(1.5)
        tap(app.buttons["Night"], hold: 1.6)
        tap(app.buttons["Cooler night"], hold: 0.7)
        tap(app.buttons["Cooler night"], hold: 1.6)
        tap(app.buttons["Dawn"], hold: 1.6)
        tap(app.buttons["Warmer dawn"], hold: 0.7)
        tap(app.buttons["Warmer dawn"], hold: 1.6)
        tap(app.buttons["Now"], hold: 2.5)
        tap(app.buttons["Right"], hold: 2.5)
        end()
    }

    func testClipSchedule() throws {
        launch(control: "dial", route: "schedule")
        XCTAssertTrue(app.staticTexts["Schedule active"].waitForExistence(timeout: 15))
        begin()
        pause(1.5)
        tap(button(prefix: "Tue"), hold: 1.2)
        tap(button(containing: "Deep"), hold: 1.4)
        tap(app.buttons["Cooler"], hold: 0.5)
        tap(app.buttons["Cooler"], hold: 0.5)
        tap(app.buttons["Cooler"], hold: 1.2)
        tap(app.buttons["Save"], hold: 3.0)
        end()
    }

    func testClipSleepAndWatch() throws {
        launch(control: "dial", route: "sleep")
        let compare = app.buttons["compareWatch"]
        XCTAssertTrue(compare.waitForExistence(timeout: 15))
        begin()
        pause(1.8)
        tap(compare, hold: 2.0)
        scroll(up: 0.35, hold: 1.6)
        scroll(up: 0.35, hold: 1.6)
        scroll(up: 0.35, hold: 2.0)
        back(hold: 2.0)
        end()
    }

    /// The full story: every tab, each temperature control, the Watch comparison and Health.
    func testWalkthrough() throws {
        launch(control: "dial")
        XCTAssertTrue(app.buttons["Decrease temperature"].waitForExistence(timeout: 15))
        begin()
        pause(1.0)

        // Temp: the dial, then both sides linked
        dragDial(from: 72, to: 78)
        pause(0.8)
        dragDial(from: 78, to: 68)
        pause(0.8)
        tap(app.buttons["Both"], hold: 1.0)
        tap(app.buttons["Left"], hold: 0.8)

        // Both-sides control, chosen from the settings sheet
        chooseControl("Both sides")
        tap(app.buttons["Warmer, Right"], hold: 0.8)
        tap(app.buttons["Cooler, Left"], hold: 1.2)

        // Night & Dawn control
        chooseControl("Night & Dawn")
        tap(app.buttons["Night"], hold: 1.0)
        tap(app.buttons["Cooler night"], hold: 0.9)
        tap(app.buttons["Dawn"], hold: 1.0)
        tap(app.buttons["Warmer dawn"], hold: 1.2)

        // Schedule
        tap(app.tabBars.buttons["Schedule"], hold: 1.8)
        tap(button(containing: "Deep"), hold: 1.2)
        tap(app.buttons["Cooler"], hold: 0.5)
        tap(app.buttons["Cooler"], hold: 1.0)
        tap(app.buttons["Save"], hold: 1.5)

        // Sleep: last night, the Watch comparison, then the week
        tap(app.tabBars.buttons["Sleep"], hold: 2.0)
        tap(app.buttons["compareWatch"], hold: 1.8)
        scroll(up: 0.35, hold: 1.4)
        scroll(up: 0.35, hold: 1.4)
        scroll(up: 0.35, hold: 1.4)
        back(hold: 1.2)
        tap(app.buttons["Week"], hold: 1.6)
        scroll(up: 0.4, hold: 2.2)

        // Apple Health, from the settings sheet
        tap(settingsButton(), hold: 1.0)
        tap(button(prefix: "Apple Health"), hold: 1.8)
        scroll(up: 0.3, hold: 1.5)
        back(hold: 0.8)
        tap(app.buttons["Close"], hold: 1.0)

        // Back to the bed
        chooseControl("Dial")
        tap(app.tabBars.buttons["Temp"], hold: 2.2)
        end()
    }

    // MARK: - Helpers

    private func launch(control: String, route: String? = nil) {
        let environment = ProcessInfo.processInfo.environment
        let appearance = environment["MARKETING_APPEARANCE"] ?? "Dark"
        app = XCUIApplication()
        app.launchArguments = ["-apiBackend", "demo", "-onboardingComplete", "YES", "-appearance", appearance,
                               "-healthSyncEnabled", "NO", "-marketingCapture", "YES", "-tempControl", control,
                               "-uiRoute", route ?? "none"]
        app.launch()
    }

    /// Flushed marks control recorder boundaries; endpoint holds keep launch/teardown out of the video.
    private func begin() { mark("begin"); pause(3) }
    private func end() { pause(0.5); mark("end"); pause(3) }
    private func mark(_ name: String) {
        print(String(format: "MARKETING_MARK %@ %.3f", name, Date().timeIntervalSince1970))
        fflush(nil)
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func tap(_ element: XCUIElement, hold: TimeInterval) {
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: 10), "Missing \(element)")
        element.tap()
        pause(hold)
    }

    private func button(prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Each tab has its own gear; tap the one on screen.
    private func settingsButton() -> XCUIElement {
        let gears = app.buttons.matching(identifier: "Settings")
        for index in 0..<gears.count where gears.element(boundBy: index).isHittable {
            return gears.element(boundBy: index)
        }
        return gears.firstMatch
    }

    private func chooseControl(_ title: String) {
        tap(settingsButton(), hold: 1.0)
        tap(button(prefix: "Temperature control"), hold: 0.8)
        tap(app.buttons[title], hold: 0.8)
        tap(app.buttons["Close"], hold: 1.2)
    }

    private func back(hold: TimeInterval) {
        tap(app.navigationBars.buttons.element(boundBy: 0), hold: hold)
    }

    /// A finger-speed drag that stops before release, so the list settles instead of flinging.
    /// `up` is the fraction of the screen height the content moves up; negative scrolls back down.
    private func scroll(up fraction: CGFloat, hold: TimeInterval) {
        let window = app.windows.firstMatch
        let startY: CGFloat = fraction > 0 ? 0.72 : 0.28
        let endY = max(0.12, min(0.88, startY - fraction * 0.6))
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let finish = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: XCUIGestureVelocity(700), thenHoldForDuration: 0.15)
        pause(hold)
    }

    /// Moves the dial knob along its arc; the dial maps 55–110°F onto 135°–405° of a 128.6pt radius.
    private func dragDial(from start: Int, to finish: Int) {
        let dial = app.descendants(matching: .any).matching(identifier: "Target temperature").firstMatch
        XCTAssertTrue(dial.exists || dial.waitForExistence(timeout: 10))
        let frame = dial.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        func point(_ value: Int) -> XCUICoordinate {
            let degrees = 135 + Double(value - 55) / 55 * 270
            let radius = 300.0 * 120 / 280
            let radians = degrees * .pi / 180
            return origin.withOffset(CGVector(dx: frame.midX + cos(radians) * radius, dy: frame.midY + sin(radians) * radius))
        }
        point(start).press(forDuration: 0.15, thenDragTo: point(finish), withVelocity: XCUIGestureVelocity(90), thenHoldForDuration: 0.2)
    }
}
