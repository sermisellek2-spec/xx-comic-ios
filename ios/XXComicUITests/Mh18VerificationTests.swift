import XCTest

final class Mh18VerificationTests: XCTestCase {
    func testManualVerificationCanCloseAndBeOpenedAgain() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tables.staticTexts["站源管理"].tap()
        let verify = app.buttons["source.verify.mh18"]
        for _ in 0..<5 where !verify.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
        verify.tap()
        let close = app.buttons["mh18.verification.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mh18.verification.retry"].exists)
        close.tap()
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
        verify.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.navigationBars["站源管理"].exists)
    }
}
