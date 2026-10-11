import XCTest

final class ReaderToolbarParityUITests: XCTestCase {
    private func openReader(paged: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"] + (paged ? ["--matrix-paged-reader"] : [])
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 10)); comic.tap()
        let read = app.buttons["detail.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5)); read.tap()
        XCTAssertTrue(app.navigationBars["第1话"].waitForExistence(timeout: 10))
        return app
    }

    func testPagedReaderToolbarChangesChaptersAndKeepsUsableActionTargets() {
        let app = openReader(paged: true)
        let previous = app.buttons["reader.previous.chapter"]
        let next = app.buttons["reader.next.chapter"]
        XCTAssertFalse(previous.isEnabled)
        XCTAssertEqual(next.label, "下一章")
        let settings = app.buttons["reader.settings"]
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["reader.directory"].frame.height, 44)
        next.tap()
        XCTAssertTrue(app.navigationBars["第2话"].waitForExistence(timeout: 5), "The toolbar must change chapters even in paged mode")
        XCTAssertTrue(previous.isEnabled)
        previous.tap()
        XCTAssertTrue(app.navigationBars["第1话"].waitForExistence(timeout: 5))
    }

    func testStripReaderToolbarRetainsDirectoryAndReaderSettings() {
        let app = openReader(paged: false)
        app.buttons["reader.directory"].tap()
        XCTAssertTrue(app.staticTexts["全部章节"].waitForExistence(timeout: 5))
        app.buttons["chapter.drawer.dismiss"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.buttons["reader.settings.close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["左右手"].exists)
    }
}
