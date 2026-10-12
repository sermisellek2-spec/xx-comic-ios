import XCTest

final class SourceSwitchParityUITests: ParityUITestCase {
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-reader-original", "--matrix-paged-reader", "--light-mode"] + flags
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10)); app.buttons["我的书架"].tap()
        return app
    }
    private func openDetail(_ app: XCUIApplication) {
        let book = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap()
        XCTAssertTrue(app.buttons["detail.switch-source"].waitForExistence(timeout: 5))
    }
    private func openCandidates(_ app: XCUIApplication) {
        app.buttons["detail.switch-source"].tap()
        XCTAssertTrue(app.buttons["source-switch.select.copy4000"].waitForExistence(timeout: 5))
    }
    private func assertPageTwo(_ app: XCUIApplication) {
        let page = app.collectionViews["reader.pages"]
        expectation(for: NSPredicate(format: "value == %@", "第1话，第 2 页，共 4 页"), evaluatedWith: page)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.images.matching(identifier: "reader.image").allElementsBoundByIndex.contains {
            $0.isHittable && ($0.value as? String)?.contains(":384x384") == true
        })
    }
    private func waitForSource(_ name: String, app: XCUIApplication) {
        let source = app.buttons["detail.switch-source"]
        expectation(for: NSPredicate(format: "label == %@", "切换站源，当前" + name), evaluatedWith: source)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["detail.read"].isHittable)
    }

    func testStrictSameTitleExcludesSimilarResultsAndKeepsTheCurrentSourceVisible() {
        let app = launch(["--matrix-switch-similar-title"]); openDetail(app); openCandidates(app)
        XCTAssertTrue(app.staticTexts["选择站源，保留收藏与阅读进度"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables["source-switch.candidates"].cells.count, 2)
        XCTAssertFalse(app.buttons["source-switch.select.gmh"].exists)
        XCTAssertFalse(app.buttons["source-switch.select.mh160"].isEnabled)
        app.buttons["source-switch.cancel"].tap()
        XCTAssertEqual(app.buttons["detail.switch-source"].label, "切换站源，当前漫画160")
    }

    func testNoExactSourceShowsEmptyFeedbackAndCanSearchAgainWithoutChangingTheBook() {
        let app = launch(["--matrix-switch-no-match"]); openDetail(app)
        app.buttons["detail.switch-source"].tap()
        XCTAssertTrue(app.staticTexts["暂未找到其他同名站源"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables["source-switch.candidates"].cells.count, 1)
        app.buttons["source-switch.retry"].tap()
        XCTAssertTrue(app.staticTexts["暂未找到其他同名站源"].waitForExistence(timeout: 5))
        app.buttons["source-switch.cancel"].tap()
        XCTAssertEqual(app.buttons["detail.switch-source"].label, "切换站源，当前漫画160")
    }

    func testEmptyTargetDirectoryPreservesTheOriginalAndARealRetryCompletesTheSwitch() {
        let app = launch(["--matrix-switch-empty-once"]); openDetail(app); openCandidates(app)
        app.buttons["source-switch.select.copy4000"].tap()
        let failure = app.alerts["换源失败"]
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertTrue(failure.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已保留原站源和阅读记录")).firstMatch.exists)
        failure.buttons["重试"].tap()
        waitForSource("拷贝漫画", app: app)
        XCTAssertEqual(app.buttons["detail.switch-source"].label, "切换站源，当前拷贝漫画")
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.navigationBars["第1话"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["reader.image"].firstMatch.waitForExistence(timeout: 5))
    }

    func testCancellingPendingSwitchKeepsTheOriginalRecordAndAllowsAnotherSwitch() {
        let app = launch(["--matrix-switch-held-until-cancel"]); openDetail(app); openCandidates(app)
        app.buttons["source-switch.select.copy4000"].tap()
        XCTAssertTrue(app.alerts["正在换源…"].waitForExistence(timeout: 5))
        app.alerts["正在换源…"].buttons["取消换源"].tap()
        XCTAssertTrue(app.buttons["source-switch.cancel"].waitForExistence(timeout: 5)); app.buttons["source-switch.cancel"].tap()
        XCTAssertEqual(app.buttons["detail.switch-source"].label, "切换站源，当前漫画160")
        XCTAssertFalse(app.alerts["换源失败"].exists)
        openCandidates(app); app.buttons["source-switch.select.copy4000"].tap()
        waitForSource("拷贝漫画", app: app)
        XCTAssertEqual(app.buttons["detail.switch-source"].label, "切换站源，当前拷贝漫画")
        app.terminate(); app.launch(); openDetail(app)
        XCTAssertEqual(app.buttons["detail.switch-source"].label, "切换站源，当前拷贝漫画")
    }

    func testReaderSwitchAndReturnRelaunchKeepPageFavoriteAndGroupOnTheNewSource() {
        let app = launch()
        app.collectionViews.cells["电锯人"].press(forDuration: 1); app.buttons["移动"].tap()
        XCTAssertTrue(app.buttons["+ 新建分组"].waitForExistence(timeout: 5)); app.buttons["+ 新建分组"].tap()
        let dialog = app.alerts["新建分组"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5)); dialog.textFields.firstMatch.tap(); dialog.textFields.firstMatch.typeText("换源保留组"); dialog.buttons["创建"].tap()
        app.navigationBars["移动至分组"].buttons["完成"].tap()
        openDetail(app); app.buttons["detail.read"].tap()
        let pages = app.collectionViews["reader.pages"]
        XCTAssertTrue(pages.waitForExistence(timeout: 10))
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); assertPageTwo(app)
        if !app.buttons["换源"].isHittable { pages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        app.buttons["换源"].tap()
        XCTAssertTrue(app.buttons["source-switch.select.copy4000"].waitForExistence(timeout: 5)); app.buttons["source-switch.select.copy4000"].tap()
        expectation(for: NSPredicate(format: "value == %@", "拷贝漫画"), evaluatedWith: app.staticTexts["reader.title"])
        waitForExpectations(timeout: 10)
        assertPageTwo(app)
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["detail.switch-source"].label, "切换站源，当前拷贝漫画")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(app.collectionViews.cells.matching(identifier: "电锯人").count, 1)
        app.collectionViews.cells["电锯人"].press(forDuration: 1); app.buttons["移动"].tap()
        let group = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "bookshelf.group.select.", "换源保留组")).firstMatch
        XCTAssertEqual(group.value as? String, "已选择")
        app.navigationBars["移动至分组"].buttons["取消"].tap()
        app.terminate(); app.launch(); openDetail(app)
        XCTAssertEqual(app.buttons["detail.switch-source"].label, "切换站源，当前拷贝漫画")
        app.buttons["detail.read"].tap(); assertPageTwo(app)
    }
}
