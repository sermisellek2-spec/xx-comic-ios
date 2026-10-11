import XCTest

final class AppNavigationTests: ParityUITestCase {
    func testNavigationAndReaderPreferencesPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        func openReadingSettings() {
            app.buttons["我的书架"].tap()
            let comic = app.collectionViews.cells["电锯人"]
            XCTAssertTrue(comic.waitForExistence(timeout: 5)); comic.tap()
            app.buttons["detail.read"].tap()
            let settings = app.buttons["reader.settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].exists)
        XCTAssertTrue(app.buttons["我的书架"].isHittable)
        XCTAssertTrue(app.buttons["本地书架"].isHittable)
        app.buttons["本地书架"].tap()
        XCTAssertTrue(app.buttons["我的书架"].isHittable)
        XCTAssertTrue(app.buttons["本地书架"].isSelected)
        openReadingSettings()
        let toggle = app.switches["reader.disable.page.animation"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        toggle.tap()
        let changed = toggle.value as? String
        XCTAssertNotEqual(original, changed)
        app.terminate()
        app.launch()
        openReadingSettings()
        XCTAssertEqual(app.switches["reader.disable.page.animation"].value as? String, changed)
        app.switches["reader.disable.page.animation"].tap()
    }
}
