import XCTest

final class Mh18VerificationTests: ParityUITestCase {
    private func scrollToVerifyButton(_ verify: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["站源管理"].waitForExistence(timeout: 5))
        _ = verify.waitForExistence(timeout: 5)
        for _ in 0..<5 {
            if verify.exists && !verify.frame.isEmpty && app.windows.firstMatch.frame.intersects(verify.frame) && verify.isHittable {
                break
            }
            app.tables.firstMatch.swipeUp()
        }
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
    }

    func testActualTimeoutRetryWithLocalHTTPResponseUpdatesManagementAndResetSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures", "--verification-fixtures", "--verification-timeout-then-local-response"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.tables.staticTexts["站源管理"].waitForExistence(timeout: 5))
        app.tables.staticTexts["站源管理"].tap()
        let verify = app.buttons["source.verify.mh18"]
        scrollToVerifyButton(verify, in: app)
        app.buttons["source.reset.mh18"].tap(); verify.tap()
        XCTAssertTrue(app.staticTexts["验证超时，请重新加载"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mh18.verification.retry"].isEnabled)
        app.buttons["mh18.verification.retry"].tap()
        XCTAssertTrue(app.tables.staticTexts["18mh.org · 已验证"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mh18.verification.close"].exists)
        XCTAssertTrue(verify.isEnabled)
        app.buttons["source.reset.mh18"].tap(); XCTAssertTrue(app.tables.staticTexts["18mh.org · 未验证"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.tables.staticTexts["站源管理"].waitForExistence(timeout: 5))
        app.tables.staticTexts["站源管理"].tap()
        scrollToVerifyButton(verify, in: app)
        XCTAssertTrue(app.tables.staticTexts["18mh.org · 未验证"].waitForExistence(timeout: 5))
        verify.tap(); XCTAssertTrue(app.buttons["mh18.verification.close"].waitForExistence(timeout: 5)); app.buttons["mh18.verification.close"].tap()
        XCTAssertTrue(app.tables.staticTexts["18mh.org · 未验证"].waitForExistence(timeout: 5))
    }
    func testManualVerificationCanCloseAndBeOpenedAgain() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures", "--verification-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.tables.staticTexts["站源管理"].waitForExistence(timeout: 5))
        app.tables.staticTexts["站源管理"].tap()
        let verify = app.buttons["source.verify.mh18"]
        scrollToVerifyButton(verify, in: app)
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
