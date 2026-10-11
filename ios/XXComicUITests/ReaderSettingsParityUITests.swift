import XCTest

final class ReaderSettingsParityUITests: ParityUITestCase {
    private func open(_ app: XCUIApplication) {
        app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 10)); comic.tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5)); app.buttons["detail.read"].tap()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 10)); app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.buttons["reader.layout.0"].waitForExistence(timeout: 5))
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-reader-original", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString; app.launch(); open(app)
        return app
    }
    func testModeThemeAndSwitchSelectionPersistAfterRelaunch() {
        let app = launch()
        app.buttons["reader.layout.1"].tap(); app.buttons["reader.theme.1"].tap()
        let crop = app.switches["reader.crop.white.margins"]
        XCTAssertTrue(crop.waitForExistence(timeout: 5))
        for _ in 0..<4 where !crop.isHittable { app.scrollViews["reader.settings.content"].swipeUp() }
        XCTAssertTrue(crop.isHittable); crop.tap()
        XCTAssertEqual(crop.value as? String, "1")
        app.buttons["reader.settings.close"].tap()
        app.terminate(); app.launch(); open(app)
        XCTAssertTrue(app.buttons["reader.layout.1"].isSelected)
        XCTAssertTrue(app.buttons["reader.theme.1"].isSelected)
        XCTAssertEqual(app.switches["reader.crop.white.margins"].value as? String, "1")
        XCTAssertFalse(app.staticTexts["左右手模式"].exists)
        XCTAssertFalse(app.staticTexts["日漫模式"].exists)
        XCTAssertFalse(app.staticTexts["翻页方式"].exists)
    }
    func testEnhancementControlsAppearOnlyWhenEnabledAndComparisonReturnsToOriginal() {
        let app = launch()
        let enabled = app.switches["reader.enhancement.enabled"]
        for _ in 0..<4 where !enabled.isHittable { app.scrollViews["reader.settings.content"].swipeUp() }
        XCTAssertTrue(enabled.isHittable)
        XCTAssertEqual(enabled.value as? String, "0")
        XCTAssertFalse(app.switches["reader.enhancement.comparison"].exists)
        enabled.tap()
        let mode = app.buttons["reader.enhancement.mode.1"]
        for _ in 0..<4 where !mode.isHittable { app.scrollViews["reader.settings.content"].swipeUp() }
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.tap()
        XCTAssertTrue(mode.isSelected)
        let comparison = app.switches["reader.enhancement.comparison"]
        XCTAssertTrue(comparison.exists)
        for _ in 0..<4 where !comparison.isHittable { app.scrollViews["reader.settings.content"].swipeUp() }
        XCTAssertTrue(comparison.isHittable); comparison.tap()
        XCTAssertEqual(comparison.value as? String, "1")
        for _ in 0..<4 where !enabled.isHittable { app.scrollViews["reader.settings.content"].swipeDown() }
        enabled.tap()
        XCTAssertFalse(comparison.exists)
        app.buttons["reader.settings.close"].tap()
        let image = app.images["reader.image"].firstMatch
        expectation(for: NSPredicate(format: "value CONTAINS ':384x384' AND NOT (value BEGINSWITH 'neural:')"), evaluatedWith: image)
        waitForExpectations(timeout: 15)
    }
}
