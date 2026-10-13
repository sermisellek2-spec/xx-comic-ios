import XCTest
import UIKit

/// Image-comic import and retired text-reader boundaries, using real owned files.
final class EpubReadingUITests: ParityUITestCase {
    private let sessionID = UUID().uuidString
    private func launch(kindle: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--epub-fixtures"] + (kindle ? ["--kindle-fixtures"] : [])
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = sessionID
        app.launch()
        XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 20)); app.buttons["本地书架"].tap()
        return app
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
    private func readyComic(_ app: XCUIApplication, chapter: String? = nil) {
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertFalse(app.buttons["排版"].exists)
        expectation(for: NSPredicate { _, _ in
            app.collectionViews.cells.count > 0 && !app.buttons["正在加载图片…"].exists && !app.buttons["图片加载失败 · 点击重试"].exists
        }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        if let chapter {
            expectation(for: NSPredicate(format: "value BEGINSWITH %@", chapter + "，"), evaluatedWith: app.collectionViews["reader.pages"])
            waitForExpectations(timeout: 5)
        }
    }
    private func open(_ title: String, app: XCUIApplication, secondChapter: Bool = false) {
        let cell = app.collectionViews.cells[title]
        XCTAssertTrue(cell.waitForExistence(timeout: 15)); cell.tap()
        XCTAssertTrue(app.buttons["章节目录"].waitForExistence(timeout: 10)); app.buttons["章节目录"].tap()
        let row = app.tables.cells.element(boundBy: secondChapter ? 1 : 0)
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
    }
    @discardableResult
    private func importFixture(_ kind: String, format: String, app: XCUIApplication) -> String {
        app.buttons["本地书架"].tap(); app.buttons["bookshelf.import"].tap()
        let item = app.buttons["验收 " + format + "·" + kind]
        let menu = app.scrollViews.containing(.button, identifier: format + " 漫画").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        for _ in 0..<4 where !item.isHittable { menu.swipeUp() }
        XCTAssertTrue(item.isHittable); item.tap()
        let alert = app.alerts["导入 " + format + " 漫画"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let title = format + " 验收·" + kind + "·" + String(UUID().uuidString.prefix(6))
        let field = alert.textFields.firstMatch; field.tap()
        if let value = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText(title); alert.buttons["导入"].tap()
        return title
    }
    private func launchKindle() -> XCUIApplication { launch(kindle: true) }
    private func importKindle(_ kind: String, app: XCUIApplication) -> String { importFixture(kind, format: "Kindle", app: app) }
    private func openKindle(_ title: String, app: XCUIApplication) { open(title, app: app) }

    func testImageEpubKeepsDirectoryAndSecondChapterResumeWithoutTextControls() {
        let app = launch(); open("EPUB 验收·图片", app: app, secondChapter: true); readyComic(app, chapter: "第二章")
        back(app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '继续阅读'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap(); readyComic(app, chapter: "第二章")
        app.terminate(); app.launch(); app.buttons["本地书架"].tap()
        app.collectionViews.cells["EPUB 验收·图片"].tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap(); readyComic(app, chapter: "第二章")
        back(app); back(app)
        let shelfResume = app.buttons["bookshelf.resume"]
        XCTAssertTrue(shelfResume.waitForExistence(timeout: 10))
        XCTAssertEqual(shelfResume.value as? String, "EPUB 验收·图片，上次看到 · 第 2 话")
        XCTAssertEqual(app.collectionViews.cells.element(boundBy: 0).label, "EPUB 验收·图片")
        shelfResume.tap(); readyComic(app, chapter: "第二章")
        app.terminate(); app.launch(); app.buttons["本地书架"].tap()
        XCTAssertTrue(shelfResume.waitForExistence(timeout: 10))
        XCTAssertEqual(shelfResume.value as? String, "EPUB 验收·图片，上次看到 · 第 2 话")
        XCTAssertEqual(app.collectionViews.cells.element(boundBy: 0).label, "EPUB 验收·图片")
        shelfResume.tap(); readyComic(app, chapter: "第二章")
    }
    func testTextAndMixedEpubImportsRejectWithoutPublishingABook() {
        let app = launch()
        for kind in ["文字", "图文", "单图带文字"] {
            let title = importFixture(kind, format: "EPUB", app: app)
            let error = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "仅支持图片漫画")).firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 15)); XCTAssertFalse(app.collectionViews.cells[title].exists)
            XCTAssertFalse(app.webViews.firstMatch.exists)
        }
        XCTAssertTrue(app.collectionViews.cells["EPUB 验收·图片"].exists)
    }
    func testLegacyTextBookStaysOnShelfAndCannotOpenATextReader() {
        let app = launch(), title = "EPUB 验收·旧文字"
        open(title, app: app)
        let alert = app.alerts["无法打开书籍"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不支持纯文字")).firstMatch.exists)
        XCTAssertFalse(alert.buttons["重试"].exists); XCTAssertFalse(app.webViews.firstMatch.exists)
        alert.buttons["取消"].tap(); back(app)
        app.terminate(); app.launch(); app.buttons["本地书架"].tap()
        XCTAssertTrue(app.collectionViews.cells[title].waitForExistence(timeout: 10))
    }
    func testImportMenuUsesComicFormatsAndEpubPickerCanBeCancelled() throws {
        let app = launch(); app.buttons["bookshelf.import"].tap()
        XCTAssertTrue(app.buttons["EPUB 漫画"].exists); XCTAssertTrue(app.buttons["Kindle 漫画"].exists)
        XCTAssertFalse(app.buttons["EPUB 电子书"].exists); XCTAssertFalse(app.buttons["Kindle 电子书"].exists)
        app.buttons["EPUB 漫画"].tap()
        try FilesPickerDriver(app: app).cancelPicker()
        XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 10))
    }

    func testKindleComicRealImportUsesExistingImageReaderAndResume() {
        let app = launchKindle(), title = importKindle("漫画", app: app)
        openKindle(title, app: app)
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        expectation(for: NSPredicate { _, _ in
            app.collectionViews.cells.count > 0
                && !app.buttons["正在加载图片…"].exists
                && !app.buttons["图片加载失败 · 点击重试"].exists
        }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        back(app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '继续阅读'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 10))
    }

    func testKindleTextAndMixedImportsRejectWithoutOpeningAWebReader() {
        let app = launchKindle()
        for kind in ["小说", "图文"] {
            let title = importKindle(kind, app: app)
            let error = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "仅支持图片漫画")).firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 15)); XCTAssertFalse(app.collectionViews.cells[title].exists)
            XCTAssertFalse(app.webViews.firstMatch.exists)
        }
    }
    func testKindleUnsupportedImportShowsParserReasonAndPickerEntryWorks() {
        let app = launchKindle()
        for kind in ["KF8", "DRM"] {
            let title = importKindle(kind, app: app)
            let error = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", kind)).firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 15)); XCTAssertFalse(app.collectionViews.cells[title].exists)
        }
        app.buttons["本地书架"].tap(); app.buttons["bookshelf.import"].tap(); app.buttons["Kindle 漫画"].tap()
        XCTAssertTrue(app.navigationBars.buttons["取消"].waitForExistence(timeout: 5)); app.navigationBars.buttons["取消"].tap()
    }
}
