import XCTest

@MainActor
final class RoomUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    /// The reported bug: after changing warmth, Back to default only appeared after
    /// leaving and reopening the Room screen.
    func testTemporaryCardAppearsRightAfterAWarmthChange() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openScreen", "room", "-openRoom", "Living room"]
        app.launch()
        let warmth = app.descendants(matching: .any)["warmth"].firstMatch
        XCTAssertTrue(warmth.waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["backToDefault"].exists)
        warmth.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["backToDefault"].firstMatch.waitForExistence(timeout: 3))
        app.descendants(matching: .any)["backToDefault"].firstMatch.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.descendants(matching: .any)["backToDefault"].firstMatch)
        waitForExpectations(timeout: 3)
    }

    func testCrownChangesBrightnessOnTheRoomScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openScreen", "room", "-openRoom", "Living room"]
        app.launch()
        let level = app.descendants(matching: .any)["brightness"].firstMatch
        XCTAssertTrue(level.waitForExistence(timeout: 20))
        XCTAssertEqual(level.label, "70%")
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.3)
        expectation(for: NSPredicate(format: "label != '70%'"), evaluatedWith: level)
        waitForExpectations(timeout: 5)

    }

    func testPinScrollAndRemoveASwatch() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openScreen", "wheel"]
        app.launch()
        let pin = app.buttons["pinColor"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["swatchHint"].exists)
        pin.tap()
        let swatch = app.descendants(matching: .any)["swatch-0"].firstMatch
        XCTAssertTrue(swatch.waitForExistence(timeout: 3), "pinning adds a swatch")
        pin.tap()
        XCTAssertFalse(app.descendants(matching: .any)["swatch-1"].exists, "the same color isn't saved twice")
        // Scroll down by dragging beside the wheel (dragging on the wheel picks a color).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.92))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.15)))
        XCTAssertTrue(swatch.isHittable, "the swatches are reachable by scrolling")
        swatch.press(forDuration: 0.9)
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: swatch)
        waitForExpectations(timeout: 3)
    }

    func testCrownScrollsTheColorScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openScreen", "wheel", "-mockSwatches", "YES"]
        app.launch()
        let swatch = app.descendants(matching: .any)["swatch-8"].firstMatch   // the last one, far below the wheel
        XCTAssertTrue(swatch.waitForExistence(timeout: 20))
        XCTAssertFalse(swatch.isHittable)
        XCUIDevice.shared.rotateDigitalCrown(delta: 1.5)
        let shown = NSPredicate(format: "hittable == true")
        expectation(for: shown, evaluatedWith: swatch)
        waitForExpectations(timeout: 5)
    }

    func testSelectingTwoColorsMakesAHybridWithAMovingToggle() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openScreen", "wheel", "-mockSwatches", "YES", "-scrollSwatches", "YES"]
        app.launch()
        let first = app.descendants(matching: .any)["swatch-0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        first.tap()
        XCTAssertFalse(app.descendants(matching: .any)["movingToggle"].exists, "one color is a single color")
        app.descendants(matching: .any)["swatch-1"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["movingToggle"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(first.value as? String, "selected")
        app.descendants(matching: .any)["swatch-2"].firstMatch.tap()   // 3 colors, 2 bulbs: forced moving
        XCTAssertTrue(app.staticTexts["More colors than bulbs, so they move."].waitForExistence(timeout: 3))
    }
}

