import XCTest

final class CurrentParityUITests: ParityUITestCase {
    private func launch(_ flags: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"] + flags
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10))
        return app
    }

    private func checkGlobalSearch(_ groupFlag: String) {
        let app = launch(groupFlag)
        app.tabBars.buttons["发现"].tap()
        app.buttons["discover.search.mode"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("电锯人\n")
        for source in ["mh160", "copy4000", "gmh"] {
            XCTAssertTrue(app.buttons["discover.global." + source].waitForExistence(timeout: 5),
                          "All enabled searchable sources must remain reachable outside the discovery group")
        }
        XCTAssertTrue(app.collectionViews.cells["电锯人"].exists)
    }

    private func openUnfavoritedDetail(_ app: XCUIApplication, title: String) {
        // Favorite refresh also loads chapters. Use a real unfavorited result
        // so it cannot consume the pending request used to exercise cancellation.
        app.tabBars.buttons["发现"].tap()
        app.buttons["discover.search.mode"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText(title + "\n")
        let source = app.buttons["discover.global.copy4000"]
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        let comic = app.collectionViews.cells[title]
        XCTAssertTrue(comic.waitForExistence(timeout: 5)); comic.tap()
    }

    func testCompletedChapterOffersRedownloadAndItsReadButtonLoadsActualOfflinePixels() {
        let app = launch("--matrix-download-network")
        app.collectionViews.cells["电锯人"].firstMatch.tap()
        app.buttons["detail.download"].tap()
        let chapters = app.tables["download.chapters"]
        XCTAssertTrue(chapters.waitForExistence(timeout: 8))
        let start = app.buttons["download.start"]
        XCTAssertEqual(start.label, "下载选中章节 (1)")
        XCTAssertTrue(start.isEnabled)
        // Android preselects the current chapter. Verify clear/reselect instead
        // of toggling that chapter off and trying to activate a disabled button.
        app.buttons["清空"].tap()
        XCTAssertFalse(start.isEnabled)
        chapters.cells.firstMatch.tap()
        XCTAssertEqual(start.label, "下载选中章节 (1)")
        XCTAssertTrue(start.isEnabled)
        start.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: chapters)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["detail.download"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["设置"].tap()
        app.tables.cells.containing(.staticText, identifier: "下载中心").firstMatch.tap()
        let tasks = app.tables["download.tasks"]
        XCTAssertTrue(tasks.buttons["阅读"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(tasks.buttons["阅读"].firstMatch.isEnabled)
        let status = tasks.staticTexts["download.task.status"].firstMatch
        guard let originalValue = status.value as? String else { XCTFail("The original task generation must be observable"); return }
        tasks.cells.firstMatch.press(forDuration: 1)
        app.buttons["重新下载此章"].tap()
        let confirmation = app.alerts["删除此章的下载文件？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["重新下载此章"].tap()
        let repaired = NSPredicate(format: "value BEGINSWITH %@ AND value != %@", "COMPLETED;", originalValue)
        expectation(for: repaired, evaluatedWith: status)
        waitForExpectations(timeout: 15)
        tasks.buttons["阅读"].firstMatch.tap()
        let image = app.images["reader.image"].firstMatch
        let decoded = NSPredicate(format: "value MATCHES %@", ".*:[1-9][0-9]*x[1-9][0-9]*.*")
        expectation(for: decoded, evaluatedWith: image)
        waitForExpectations(timeout: 15)
    }

    func testGlobalSearchIncludesEnabledSourcesOutsideCurrentGroup() {
        checkGlobalSearch("--matrix-single-source-group")
    }

    func testEmptyDiscoveryGroupDoesNotBlockGlobalSearch() {
        checkGlobalSearch("--matrix-empty-group")
    }

    func testDiscoveryToolsCollapseOnUpwardDragAndReturnOnDownwardDrag() {
        let app = launch("--matrix-large-bookshelf")
        app.tabBars.buttons["发现"].tap()
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells["电锯人"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields.firstMatch.isHittable)
        list.swipeUp()
        XCTAssertFalse(app.searchFields.firstMatch.isHittable)
        list.swipeDown()
        XCTAssertTrue(app.searchFields.firstMatch.isHittable)
    }

    func testDetailDownloadLoadsOnDemandDirectoryAndCloses() {
        let app = launch("--matrix-lazy-directory")
        app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 5)); comic.tap()
        app.buttons["detail.download"].tap()
        let directory = app.tables["download.chapters"]
        XCTAssertTrue(directory.waitForExistence(timeout: 5))
        XCTAssertEqual(directory.cells.count, 6)
        app.buttons["download.close"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
    }

    func testBookshelfDownloadLoadsDirectoryAndReturnsToBookshelf() {
        let app = launch("--matrix-lazy-directory")
        app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 5)); comic.press(forDuration: 1.2)
        app.buttons["下载"].tap()
        let directory = app.tables["download.chapters"]
        XCTAssertTrue(directory.waitForExistence(timeout: 5))
        XCTAssertEqual(directory.cells.count, 6)
        app.buttons["download.close"].tap()
        XCTAssertTrue(app.tabBars.buttons["书架"].isHittable)
        XCTAssertTrue(comic.exists)
    }

    func testEmptyDirectoryOffersRetryInsteadOfEmptySelection() {
        let app = launch("--matrix-lazy-directory", "--matrix-empty-directory")
        app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 5)); comic.tap()
        app.buttons["detail.download"].tap()
        XCTAssertTrue(app.buttons["暂无章节，请稍后重试 · 点击重试"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tables["download.chapters"].exists)
    }

    func testCancellingDirectoryLoadDoesNotOpenLateSelectionAndCanRetry() {
        let app = launch("--matrix-lazy-directory", "--matrix-directory-held-until-cancel")
        openUnfavoritedDetail(app, title: "电锯人")
        let download = app.buttons["detail.download"]
        download.tap()
        XCTAssertTrue(app.buttons["正在加载目录 · 点击取消"].waitForExistence(timeout: 3))
        download.tap()
        XCTAssertTrue(app.buttons["下载章节"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tables["download.chapters"].exists)
        download.tap()
        XCTAssertTrue(app.tables["download.chapters"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.tables["download.chapters"].cells.count, 6)
    }

    func testLateDetailSuccessKeepsDownloadFailureAndItsRetryAction() {
        let app = launch("--matrix-lazy-directory", "--matrix-initial-detail-after-directory", "--matrix-directory-empty-once")
        // Only mh160 fixtures are favorites. Use the unfavorited copy4000
        // result so background update checks cannot consume its first detail.
        app.tabBars.buttons["发现"].tap()
        app.buttons["discover.search.mode"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("电锯人\n")
        let source = app.buttons["discover.global.copy4000"]
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 5)); comic.tap()
        let detail = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "验收作者")).firstMatch
        XCTAssertFalse(detail.exists, "The initial detail must still be pending before download starts")
        app.buttons["detail.download"].tap()
        let feedback = app.buttons["detail.feedback"]
        let failure = "暂无章节，请稍后重试 · 点击重试"
        XCTAssertTrue(app.buttons[failure].waitForExistence(timeout: 5))
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "The initial detail must finish after the download error")
        XCTAssertEqual(feedback.label, failure)
        feedback.tap()
        XCTAssertTrue(app.tables["download.chapters"].waitForExistence(timeout: 5), "Retry must reload download chapters")
        XCTAssertEqual(app.tables["download.chapters"].cells.count, 6)
    }

    func testStartingDownloadCancelsPendingReadAndReturnsToDetail() {
        let app = launch("--matrix-lazy-directory", "--matrix-directory-held-until-cancel")
        openUnfavoritedDetail(app, title: "间谍过家家")
        let read = app.buttons["detail.read"]
        read.tap()
        XCTAssertTrue(app.buttons["正在加载章节…"].waitForExistence(timeout: 3))
        app.buttons["detail.download"].tap()
        XCTAssertTrue(app.tables["download.chapters"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.tables["download.chapters"].cells.count, 6)
        app.buttons["download.close"].tap()
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        XCTAssertTrue(read.isEnabled)
        XCTAssertFalse(app.images["reader.image"].exists)
    }

    func testStartingReadCancelsPendingDownload() {
        let app = launch("--matrix-lazy-directory", "--matrix-directory-held-until-cancel")
        openUnfavoritedDetail(app, title: "间谍过家家")
        app.buttons["detail.download"].tap()
        XCTAssertTrue(app.buttons["正在加载目录 · 点击取消"].waitForExistence(timeout: 3))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.images["reader.image"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.tables["download.chapters"].exists)
    }

    func testCancelledDownloadAfterPendingReadCanOpenReaderAgain() {
        let app = launch("--matrix-lazy-directory", "--matrix-directory-held-twice-until-cancel")
        openUnfavoritedDetail(app, title: "间谍过家家")
        let read = app.buttons["detail.read"], download = app.buttons["detail.download"]
        read.tap()
        XCTAssertTrue(app.buttons["正在加载章节…"].waitForExistence(timeout: 3))
        download.tap()
        XCTAssertTrue(app.buttons["正在加载目录 · 点击取消"].waitForExistence(timeout: 3))
        download.tap()
        XCTAssertTrue(read.isEnabled)
        read.tap()
        XCTAssertTrue(app.images["reader.image"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.tables["download.chapters"].exists)
    }
}
