import XCTest

/// Grid › bookmark › Saved lights. (Typing a name can't be driven on the watch simulator,
/// so saving and renaming are unit-tested in ConfigTests; these use preloaded configurations.)
@MainActor
final class ConfigsUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    func testTappingASavedConfigurationLoadsItAndGoesBackToTheGrid() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockConfigs", "YES"]
        app.launch()
        let living = app.descendants(matching: .any)["tile-Living room"].firstMatch
        XCTAssertTrue(living.waitForExistence(timeout: 20))
        XCTAssertNotEqual(living.value as? String, "Off")
        app.descendants(matching: .any)["configs"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["saveCurrent"].firstMatch.waitForExistence(timeout: 5))
        let everythingOff = app.descendants(matching: .any)["config-Everything off"].firstMatch
        XCTAssertTrue(everythingOff.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rename-Everything off"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["overwrite-Everything off"].firstMatch.exists)
        everythingOff.tap()
        XCTAssertTrue(living.waitForExistence(timeout: 5))       // back on the grid
        let off = NSPredicate(format: "value == %@", "Off")
        expectation(for: off, evaluatedWith: living)
        waitForExpectations(timeout: 5)
    }
}
