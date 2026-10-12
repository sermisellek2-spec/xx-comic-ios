import XCTest

final class SettingsParityUITests: ParityUITestCase {
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"] + flags
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap()
        return app
    }

    private func openItem(_ identifier: String, app: XCUIApplication) {
        let cell = app.tables.cells[identifier]
        for _ in 0..<6 where !cell.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertTrue(cell.waitForExistence(timeout: 5)); XCTAssertTrue(cell.isHittable); cell.tap()
    }
    private func dismissAlert(_ app: XCUIApplication, button: String) {
        app.alerts.buttons[button].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.alerts.firstMatch)
        waitForExpectations(timeout: 5)
    }

    func testUpdateFailureRetryShowsNewVersionAndBrowserInstallationHint() {
        let app = launch(["--matrix-update-fixture", "--matrix-update-fail-once"])
        openItem("settings.update", app: app)
        XCTAssertTrue(app.alerts["检查更新失败"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.buttons["查看发布页"].exists)
        app.alerts.buttons["重试"].tap()
        let release = app.alerts["发现新版本 XX Comic 2.0.41"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        XCTAssertTrue(release.staticTexts.matching(NSPredicate(format: "label CONTAINS '验收新版本说明' AND label CONTAINS '下载 IPA' AND label CONTAINS '签名工具'")).firstMatch.exists)
        XCTAssertTrue(release.buttons["浏览器更新"].isHittable)
        dismissAlert(app, button: "稍后")
        XCTAssertTrue(app.tables.cells["settings.update"].isHittable)
    }

    func testCurrentVersionAndCancelledCheckAllowAnotherRealHTTPRequest() {
        var app = launch(["--matrix-update-fixture", "--matrix-update-current"])
        openItem("settings.update", app: app)
        XCTAssertTrue(app.alerts["已经是最新版本"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.staticTexts["XX Comic 2.0.40 (340)"].exists)
        dismissAlert(app, button: "知道了"); app.terminate()
        app = launch(["--matrix-update-fixture", "--matrix-update-hold-once"])
        openItem("settings.update", app: app)
        XCTAssertTrue(app.alerts["检查更新中…"].waitForExistence(timeout: 5))
        dismissAlert(app, button: "取消")
        openItem("settings.update", app: app)
        XCTAssertTrue(app.alerts["发现新版本 XX Comic 2.0.41"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts["检查更新失败"].exists)
        dismissAlert(app, button: "稍后")
    }

    func testStatisticsCancelDisableRelaunchAndEnableUseTheRealSavedSetting() {
        let app = launch()
        openItem("settings.statistics", app: app)
        XCTAssertTrue(app.alerts.buttons["关闭统计"].waitForExistence(timeout: 5))
        dismissAlert(app, button: "取消")
        XCTAssertTrue(app.tables.cells["settings.statistics"].staticTexts["已开启"].exists)
        openItem("settings.statistics", app: app); dismissAlert(app, button: "关闭统计")
        XCTAssertTrue(app.tables.cells["settings.statistics"].staticTexts["已关闭"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        openItem("settings.statistics", app: app)
        XCTAssertTrue(app.alerts.buttons["开启统计"].waitForExistence(timeout: 5))
        dismissAlert(app, button: "开启统计")
        XCTAssertTrue(app.tables.cells["settings.statistics"].staticTexts["已开启"].exists)
    }

    func testLaunchShelfPersistsAndAboutCountsOnlyTheCurrent51Sources() {
        let app = launch(["--matrix-catalog-fixtures"])
        openItem("settings.launch", app: app)
        app.tables.staticTexts["本地书架"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tables.cells["settings.launch"].staticTexts["本地书架"].exists)
        openItem("settings.about", app: app)
        XCTAssertTrue(app.tables.staticTexts["2.0.40 (340)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tables.staticTexts["51 个"].exists)
        XCTAssertFalse(app.tables.staticTexts["53 个"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["bookshelf.tab.1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["bookshelf.tab.1"].isSelected)
    }

    func testHistoryClearCancellationAndConfirmationPreserveFavoritesAcrossRelaunch() {
        let app = launch()
        openItem("settings.history", app: app)
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["清空"].tap(); dismissAlert(app, button: "取消")
        XCTAssertTrue(app.collectionViews.cells["电锯人"].exists)
        app.navigationBars.buttons["清空"].tap(); dismissAlert(app, button: "清空")
        expectation(for: NSPredicate { _, _ in app.collectionViews.cells.count == 0 }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tables.cells["settings.history"].staticTexts["0 条"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10)); app.buttons["我的书架"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.tables.cells["settings.history"].staticTexts["0 条"].waitForExistence(timeout: 5))
    }

    func testSettingsUsesCurrentAndroidSectionsAndThemeDrawer() {
        let app = launch()
        XCTAssertEqual(app.tables.cells.count, 11)
        XCTAssertFalse(app.tables.staticTexts["阅读设置"].exists)
        app.tables.cells["settings.theme"].tap()
        XCTAssertTrue(app.buttons["theme.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["theme.1"].exists)
        XCTAssertTrue(app.buttons["theme.2"].exists)
        app.buttons["theme.close"].tap()
        XCTAssertTrue(app.tables.cells["settings.theme"].isHittable)
    }

    func testThemeChoicePersistsAcrossRestart() {
        let app = launch()
        app.tables.cells["settings.theme"].tap()
        app.buttons["theme.2"].tap()
        XCTAssertTrue(app.tables.staticTexts["黑夜"].waitForExistence(timeout: 5))
        app.terminate()
        // Remove the explicit initial theme flag so persistence determines the relaunch.
        app.launchArguments = ["--ui-testing", "--matrix-fixtures"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.tables.staticTexts["黑夜"].waitForExistence(timeout: 5))
        app.tables.cells["settings.theme"].tap()
        XCTAssertTrue(app.buttons["theme.2"].isSelected)
    }

    func testCacheCleanupKeepsLibraryAndFixtureDiscovery() {
        let app = launch()
        app.tables.cells["settings.cache"].tap()
        app.buttons["确认清理"].tap()
        app.buttons["立即清理"].tap()
        let notice = app.staticTexts["缓存已清理，收藏与本地漫画已保留"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["确认清理"].isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["书架"].tap()
        app.buttons["我的书架"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
    }
}
