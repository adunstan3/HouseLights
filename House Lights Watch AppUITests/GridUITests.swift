import XCTest

/// Interaction checks for the Rooms grid against the mock bridge.
@MainActor
final class GridUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + args
        app.launch()
        return app
    }

    private func tile(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["tile-\(name)"].firstMatch
    }

    func testTapTogglesARoom() {
        let app = launch()
        let bedroom = tile(app, "Bedroom")
        XCTAssertTrue(bedroom.waitForExistence(timeout: 20))
        XCTAssertEqual(bedroom.value as? String, "Off")
        bedroom.tap()
        XCTAssertEqual(bedroom.value as? String, "40 percent")
        bedroom.tap()
        XCTAssertEqual(bedroom.value as? String, "Off")
    }

    func testHoldOpensRoomAndDoesNotToggle() {
        let app = launch()
        let living = tile(app, "Living room")
        XCTAssertTrue(living.waitForExistence(timeout: 20))
        living.press(forDuration: 0.8)
        let back = app.descendants(matching: .any)["back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "hold should open the Room screen")
        back.tap()
        XCTAssertTrue(living.waitForExistence(timeout: 5))
        XCTAssertEqual(living.value as? String, "70 percent", "a hold must not also toggle")
    }

    func testCrownBrightensRoomsThatAreOn() {
        let app = launch(["-pillSeconds", "10"])
        let living = tile(app, "Living room")
        let bedroom = tile(app, "Bedroom")
        XCTAssertTrue(living.waitForExistence(timeout: 20))
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.5)
        let pill = app.descendants(matching: .any)["crownPill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the Brighter/Dimmer pill shows while turning")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "crown-pill"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(pill.label, "Brighter · 3 on")   // living room, kitchen, office; zones don't count
        let brighter = NSPredicate(format: "value != '70 percent'")
        expectation(for: brighter, evaluatedWith: living)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(bedroom.value as? String, "Off", "rooms that are off are untouched")
    }

    func testCrownDoesNotScrollTheBigGrid() {
        let app = launch(["-mockTiles", "12"])
        let first = tile(app, "Living room")
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        let before = first.frame
        XCUIDevice.shared.rotateDigitalCrown(delta: 1.0)
        sleep(1)
        XCTAssertEqual(first.frame.minY, before.minY, accuracy: 1, "the Crown must change brightness, not scroll")
    }
}
