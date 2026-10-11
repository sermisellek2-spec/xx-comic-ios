import XCTest

final class BookshelfParityUITests: ParityUITestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"] + (large ? ["--matrix-large-bookshelf"] : [])
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10)); app.buttons["我的书架"].tap()
        return app
    }

    func testActualUnreadCountLatestChapterAndReadingPositionAppearInGridAndList() {
        let app = launch()
        let read = app.collectionViews.cells["电锯人"], unread = app.collectionViews.cells["间谍过家家"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertEqual(read.value as? String, "未读 5 · 更新至 第6话")
        XCTAssertEqual(unread.value as? String, "未读 6 · 更新至 第6话")
        app.buttons["bookshelf.layout"].tap()
        XCTAssertEqual(read.value as? String, "未读 5 · 更新至 第6话")
        XCTAssertEqual(unread.value as? String, "未读 6 · 更新至 第6话")
    }

    func testSwitchingGridToListKeepsVisibleComic() {
        let app = launch(large: true)
        let list = app.collectionViews.firstMatch
        list.swipeUp(); list.swipeUp()
        let visible = list.cells.allElementsBoundByIndex.first { $0.isHittable && $0.label.hasPrefix("验收漫画") }
        XCTAssertNotNil(visible)
        guard let title = visible?.label else { return }
        app.buttons["bookshelf.layout"].tap()
        XCTAssertTrue(list.cells[title].isHittable, "Layout switching must keep a visible book instead of returning to the top")
    }
}
