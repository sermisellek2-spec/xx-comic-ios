import XCTest

final class SourceDrawerTests: XCTestCase {
    func testSourceDraftIsDiscardedOnCloseAndAppliedOnConfirm() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["发现"].tap()
        let source = app.buttons["discover.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        let original = source.label
        source.tap()
        let candidate = app.buttons["filter.source.bbyin"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        candidate.tap()
        app.buttons["filter.close"].tap()
        XCTAssertEqual(source.label, original)
        source.tap()
        app.buttons["filter.source.bbyin"].tap()
        app.buttons["filter.confirm"].tap()
        XCTAssertTrue(source.label.contains("比卡漫画"))
    }
}
