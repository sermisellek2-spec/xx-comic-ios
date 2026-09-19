import XCTest

final class AppNavigationTests: XCTestCase {
    func testNavigationAndReaderPreferencesPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].exists)
        app.tabBars.buttons["设置"].tap()
        app.tables.staticTexts["阅读设置"].tap()
        let toggle = app.switches["reader.disable.page.animation"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        toggle.tap()
        let changed = toggle.value as? String
        XCTAssertNotEqual(original, changed)
        app.terminate()
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tables.staticTexts["阅读设置"].tap()
        XCTAssertEqual(app.switches["reader.disable.page.animation"].value as? String, changed)
        app.switches["reader.disable.page.animation"].tap()
    }
}
