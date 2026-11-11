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
}
