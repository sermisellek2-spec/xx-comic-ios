import XCTest

final class SettingsParityUITests: ParityUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap()
        return app
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
