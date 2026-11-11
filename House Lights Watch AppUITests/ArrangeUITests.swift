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
        // Back on the grid, the living room is now third.
        app.descendants(matching: .any)["back"].firstMatch.tap()
        app.descendants(matching: .any)["back"].firstMatch.tap()
        let tile = app.descendants(matching: .any)["tile-Living room"].firstMatch
        let kitchen = app.descendants(matching: .any)["tile-Kitchen"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(tile.frame.minX, kitchen.frame.minX)
    }
}
