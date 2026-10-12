import XCTest

final class Mh18VerificationTests: ParityUITestCase {
    func testActualTimeoutRetryWithLocalHTTPResponseUpdatesManagementAndResetSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures", "--verification-fixtures", "--verification-timeout-then-local-response"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        app.tables.staticTexts["站源管理"].tap()
        let verify = app.buttons["source.verify.mh18"]
        for _ in 0..<5 where !verify.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertTrue(verify.waitForExistence(timeout: 5)); app.buttons["source.reset.mh18"].tap(); verify.tap()
        XCTAssertTrue(app.staticTexts["验证超时，请重新加载"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mh18.verification.retry"].isEnabled)
        app.buttons["mh18.verification.retry"].tap()
        XCTAssertTrue(app.tables.staticTexts["18mh.org · 已验证"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mh18.verification.close"].exists)
        XCTAssertTrue(verify.isEnabled)
        app.buttons["source.reset.mh18"].tap(); XCTAssertTrue(app.tables.staticTexts["18mh.org · 未验证"].exists)
        app.terminate(); app.launch(); app.tabBars.buttons["设置"].tap(); app.tables.staticTexts["站源管理"].tap()
        for _ in 0..<5 where !verify.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertTrue(app.tables.staticTexts["18mh.org · 未验证"].waitForExistence(timeout: 5))
        verify.tap(); XCTAssertTrue(app.buttons["mh18.verification.close"].waitForExistence(timeout: 5)); app.buttons["mh18.verification.close"].tap()
        XCTAssertTrue(app.tables.staticTexts["18mh.org · 未验证"].waitForExistence(timeout: 5))
    }
    func testManualVerificationCanCloseAndBeOpenedAgain() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures", "--verification-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tables.staticTexts["站源管理"].tap()
        let verify = app.buttons["source.verify.mh18"]
        for _ in 0..<5 where !verify.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
        app.buttons["source.reset.mh18"].tap()
        XCTAssertTrue(app.tables.staticTexts["18mh.org · 未验证"].exists)
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
