import XCTest

/// A real drag on the Arrange screen. Synthesized drags can be unreliable on watchOS,
/// so the drag rules themselves are unit-tested in ArrangeDragTests.
@MainActor
final class ArrangeUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    func testDraggingMovesATileAndTheGridKeepsTheOrder() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openScreen", "arrange"]
        app.launch()
        let living = app.descendants(matching: .any)["arrange-Living room"].firstMatch
        let bedroom = app.descendants(matching: .any)["arrange-Bedroom"].firstMatch
        XCTAssertTrue(living.waitForExistence(timeout: 20))
        let start = living.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = bedroom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertEqual(living.value as? String, "position 3 of 6")
        XCTAssertEqual(bedroom.value as? String, "position 2 of 6")
        // Back (straight to the grid): the living room is now third.
        app.descendants(matching: .any)["back"].firstMatch.tap()
        let tile = app.descendants(matching: .any)["tile-Living room"].firstMatch
        let kitchen = app.descendants(matching: .any)["tile-Kitchen"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(tile.frame.minX, kitchen.frame.minX)
    }
}

@MainActor
final class NavigationUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    /// Back from Settings or any Settings page goes straight to the grid.
    func testBackFromSettingsPagesGoesToTheGrid() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let tile = app.descendants(matching: .any)["tile-Living room"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        let back = app.descendants(matching: .any)["back"].firstMatch

        // The toolbar button is reported twice (same frame) by the accessibility tree.
        let gear = app.buttons["gear"].firstMatch
        gear.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists, "one back from Settings reaches the grid")

        gear.tap()
        app.staticTexts["Arrange rooms"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["arrange-Living room"].firstMatch.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists, "back from Arrange skips Settings")
    }
}
