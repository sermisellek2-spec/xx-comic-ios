import XCTest

final class LinkedFolderParityUITests: ParityUITestCase {
    private func launch(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-empty-library", "--linked-folder-fixture", "--light-mode"] + flags
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); XCTAssertTrue(app.buttons["bookshelf.tab.1"].waitForExistence(timeout: 10))
        app.buttons["bookshelf.tab.1"].tap()
        XCTAssertTrue(app.collectionViews.cells["直读验收漫画"].waitForExistence(timeout: 10))
        return app
    }
    private func read(_ app: XCUIApplication) {
        app.tabBars.buttons["书架"].tap()
        app.buttons["bookshelf.tab.1"].tap()
        let book = app.collectionViews.cells["直读验收漫画"]
        XCTAssertTrue(book.waitForExistence(timeout: 5)); book.tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5)); app.buttons["detail.read"].tap()
        let decoded = app.images.matching(identifier: "reader.image").matching(NSPredicate(format: "value CONTAINS %@", "32x48")).firstMatch
        XCTAssertTrue(decoded.waitForExistence(timeout: 10), "Read a real external-index page through the production image consumer")
    }
    func testIndexedBookReadsRealPageWithoutAFullPrivateCopy() {
        let app = launch(); read(app)
    }
    func testMovedFolderReauthorizationRestoresReadingAndKeepsOneBook() {
        let app = launch(flags: ["--linked-folder-moved", "--linked-folder-reauthorize-selection"])
        app.tabBars.buttons["设置"].tap(); app.cells["settings.storage"].tap()
        let folder = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "local.folder.")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5)); folder.tap()
        XCTAssertTrue(app.alerts["重新授权《直读验收漫画》"].waitForExistence(timeout: 5))
        app.alerts.buttons["选择文件夹"].tap()
        XCTAssertTrue(app.staticTexts["已恢复授权；书名和阅读记录保留"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        read(app)
    }
    func testCancellingFolderReauthorizationKeepsTheExistingLink() {
        let app = launch()
        app.tabBars.buttons["设置"].tap(); app.cells["settings.storage"].tap()
        let folder = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "local.folder.")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5)); let before = folder.label; folder.tap()
        XCTAssertTrue(app.alerts["重新授权《直读验收漫画》"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap(); XCTAssertEqual(folder.label, before)
        app.navigationBars.buttons.element(boundBy: 0).tap(); read(app)
    }
}
