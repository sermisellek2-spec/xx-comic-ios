import XCTest

final class LocalDeletionParityUITests: XCTestCase {
    private func selectRealImportedBook() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--epub-fixtures", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tables.staticTexts["本地存储管理"].tap()
        let book = app.tables.staticTexts["EPUB 验收·图片"]
        for _ in 0..<8 where !book.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap()
        app.buttons["删除选中"].tap()
        app.alerts.buttons["删除"].tap()
        return app
    }

    func testWholeBookUndoRestoresSelectionPageAndRealImportedCopy() {
        let app = selectRealImportedBook()
        let undo = app.buttons["local.deletion.action"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2)); XCTAssertEqual(undo.label, "撤销"); undo.tap()
        XCTAssertTrue(app.tables.staticTexts["EPUB 验收·图片"].waitForExistence(timeout: 5))
        app.tabBars.buttons["书架"].tap()
        app.buttons["本地书架"].tap()
        let book = app.collectionViews.cells["EPUB 验收·图片"]
        for _ in 0..<6 where !book.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(book.waitForExistence(timeout: 5)); book.tap()
        app.buttons["章节目录"].tap()
        XCTAssertTrue(app.tables.cells.firstMatch.waitForExistence(timeout: 10)); app.tables.cells.firstMatch.tap()
        XCTAssertTrue(app.collectionViews.cells.firstMatch.waitForExistence(timeout: 10))
    }

    func testWholeBookDeletionWaitsForUndoWindowAndShowsActualCompletion() {
        let app = selectRealImportedBook()
        let feedback = app.staticTexts["local.deletion.message"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 2))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "已删除 App 副本"), evaluatedWith: feedback)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.tables.staticTexts["EPUB 验收·图片"].exists)
        app.tabBars.buttons["书架"].tap()
        app.buttons["我的书架"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5), "Deleting a local copy must preserve online favorites")
    }
}
