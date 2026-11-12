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
        XCTAssertEqual(bedroom.value as? String, "position 1 of 6")   // moved to the nearest free spot
        // Back (straight to the grid): the living room is now third.
        app.descendants(matching: .any)["back"].firstMatch.tap()
        let tile = app.descendants(matching: .any)["tile-Living room"].firstMatch
        let kitchen = app.descendants(matching: .any)["tile-Kitchen"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(tile.frame.minX, kitchen.frame.minX)
    }
}

@MainActor
final class FreePlacementUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    /// A room dropped half-way between two columns on the empty bottom row stays there, and
    /// the grid keeps the gap where it came from.
    func testDropHalfWayAndTheGridKeepsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openScreen", "arrange"]
        app.launch()
        func tile(_ name: String) -> XCUIElement { app.descendants(matching: .any)["arrange-\(name)"].firstMatch }
        XCTAssertTrue(tile("Living room").waitForExistence(timeout: 20))
        let living = tile("Living room").frame, office = tile("Office").frame, door = tile("Front door").frame
        // Half-way between the first two columns, one row below Office.
        let target = CGPoint(x: (office.midX + door.midX) / 2, y: office.midY + (office.midY - living.midY))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: living.midX, dy: living.midY))
            .press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: target.x, dy: target.y)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertEqual(tile("Living room").value as? String, "position 6 of 6")

        app.descendants(matching: .any)["back"].firstMatch.tap()
        let grid = { (name: String) in app.descendants(matching: .any)["tile-\(name)"].firstMatch }
        XCTAssertTrue(grid("Living room").waitForExistence(timeout: 5))
        let l = grid("Living room").frame, o = grid("Office").frame, d = grid("Front door").frame
        XCTAssertEqual(l.midX, (o.midX + d.midX) / 2, accuracy: 2, "half-way between the first two columns")
        XCTAssertGreaterThan(l.minY, o.maxY, "on the row below")
        XCTAssertEqual(grid("Kitchen").frame.minY, o.minY - (o.minY - grid("Kitchen").frame.minY), accuracy: 1)
        XCTAssertGreaterThan(grid("Kitchen").frame.minX, o.minX + 10, "Kitchen didn't slide left into the gap")
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
