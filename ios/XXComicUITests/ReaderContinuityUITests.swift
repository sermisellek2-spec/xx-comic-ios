import XCTest

final class ReaderContinuityUITests: ParityUITestCase {
    private func launch(_ extra: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-reader-original", "--matrix-download-network", "--light-mode"] + extra
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); enterReader(app)
        return app
    }
    private func enterReader(_ app: XCUIApplication) {
        app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 10)); comic.tap()
        read(app)
    }
    private func read(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5)); app.buttons["detail.read"].tap()
        let image = app.images["reader.image"].firstMatch
        expectation(for: NSPredicate(format: "value CONTAINS ':384x384'"), evaluatedWith: image)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.collectionViews["reader.pages"].exists)
    }
    private func revealControls(_ app: XCUIApplication) {
        if !app.buttons["reader.settings"].isHittable {
            app.collectionViews["reader.pages"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        waitForControls(app, visible: true)
        XCTAssertTrue(app.buttons["reader.settings"].isHittable)
    }
    private func waitForControls(_ app: XCUIApplication, visible: Bool) {
        // A single tap waits for the production double-tap recognizer to fail.
        // Synchronize that transition without removing the visibility assertion.
        let settings = app.buttons["reader.settings"]
        let predicate = NSPredicate { _, _ in (settings.exists && settings.isHittable) == visible }
        let changed = XCTNSPredicateExpectation(predicate: predicate, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
    }
    private func scrollToChapter(_ chapter: String, in app: XCUIApplication) {
        let pages = app.collectionViews["reader.pages"]
        let target = NSPredicate(format: "value CONTAINS %@", chapter)
        for _ in 0..<12 {
            if target.evaluate(with: pages) { return }
            pages.swipeUp()
        }
        XCTAssertTrue(target.evaluate(with: pages), "Continuous scrolling must reach the next chapter through the production strip")
    }
    private func reachFooter(_ app: XCUIApplication) -> XCUIElement {
        let footer = app.buttons["reader.continuation"]
        let pages = app.collectionViews["reader.pages"]
        func visible() -> Bool {
            footer.exists && footer.frame.width > 0 && footer.frame.minY >= pages.frame.minY && footer.frame.maxY <= pages.frame.maxY + 1
        }
        for _ in 0..<12 where !visible() { pages.swipeUp() }
        XCTAssertTrue(visible(), "The loading/end footer is intentionally disabled, but must be visible")
        return footer
    }
    private func checkFixedCanvas(paged: Bool) {
        let app = paged ? launch("--matrix-paged-reader") : launch()
        let pages = app.collectionViews["reader.pages"]
        let image = app.images["reader.image"].firstMatch
        XCTAssertTrue(app.buttons["reader.settings"].isHittable, "Frozen Android starts with the controls visible")
        XCTAssertFalse(app.statusBars.firstMatch.exists, "阅读页展开控制条时也应隐藏系统状态栏")
        let canvas = pages.frame, imageFrame = image.frame
        let center = pages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()
        waitForControls(app, visible: false)
        XCTAssertFalse(app.buttons["reader.settings"].isHittable)
        XCTAssertEqual(pages.frame.minY, canvas.minY, accuracy: 1)
        XCTAssertEqual(pages.frame.height, canvas.height, accuracy: 1)
        XCTAssertEqual(image.frame.minY, imageFrame.minY, accuracy: 1)
        XCTAssertEqual(image.frame.height, imageFrame.height, accuracy: 1)
        center.tap(); revealControls(app)
        XCTAssertFalse(app.statusBars.firstMatch.exists)
        XCTAssertEqual(pages.frame.minY, canvas.minY, accuracy: 1)
        XCTAssertEqual(image.frame.minY, imageFrame.minY, accuracy: 1)
        XCTAssertEqual(app.staticTexts["reader.title"].label, "电锯人 · 第1话")
        let screenshot = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        screenshot.name = paged ? "reader-fixed-canvas-paged" : "reader-fixed-canvas-strip"
        screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testStripControlsDoNotMoveOrResizeImages() { checkFixedCanvas(paged: false) }
    func testPagedControlsDoNotMoveOrResizeImages() { checkFixedCanvas(paged: true) }

    func testContinuousChapterLocalSeekModeSwitchAndRelaunchResume() {
        let app = launch()
        scrollToChapter("第2话", in: app)
        let pages = app.collectionViews["reader.pages"]
        XCTAssertFalse(app.buttons["reader.settings"].isHittable, "Dragging must collapse controls")
        revealControls(app)
        app.sliders["reader.seek"].adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(pages.value as? String, "第2话，第 1 页，共 4 页")
        // A chapter-local seek must not jump to the first chapter of the strip.
        app.buttons["reader.settings"].tap(); app.buttons["reader.layout.1"].tap()
        app.buttons["reader.settings.close"].tap()
        XCTAssertEqual(pages.value as? String, "第2话，第 1 页，共 4 页")
        app.buttons["reader.settings"].tap(); app.buttons["reader.layout.0"].tap()
        app.buttons["reader.settings.close"].tap()
        XCTAssertEqual(pages.value as? String, "第2话，第 1 页，共 4 页")
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); enterReader(app)
        XCTAssertEqual(app.collectionViews["reader.pages"].value as? String, "第2话，第 1 页，共 4 页")
        XCTAssertEqual(app.staticTexts["reader.title"].label, "电锯人 · 第2话")
    }

    func testNextChapterFailureKeepsReadablePagesAndHasExplicitRetry() {
        let app = launch("--matrix-continuation-fail-once")
        let footer = reachFooter(app)
        XCTAssertEqual(footer.label, "下一章加载失败 · 点击重试")
        XCTAssertTrue(footer.isHittable)
        XCTAssertTrue(app.images["reader.image"].firstMatch.exists)
        XCTAssertTrue((app.collectionViews["reader.pages"].value as? String ?? "").contains("第1话"))
        footer.tap(); scrollToChapter("第2话", in: app)
        XCTAssertTrue((app.collectionViews["reader.pages"].value as? String ?? "").contains("共 4 页"))
        XCTAssertFalse(app.buttons["下一章加载失败 · 点击重试"].exists)
    }

    func testLeavingReaderCancelsPendingContinuationAndReopenCanLoadIt() {
        let app = launch("--matrix-continuation-held-once")
        let footer = reachFooter(app)
        XCTAssertEqual(footer.label, "正在加载下一章…")
        revealControls(app); app.buttons["reader.back"].tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.collectionViews["reader.pages"].exists)
        XCTAssertFalse(app.buttons["下一章加载失败 · 点击重试"].exists)
        read(app); scrollToChapter("第2话", in: app)
        XCTAssertTrue((app.collectionViews["reader.pages"].value as? String ?? "").contains("共 4 页"))
    }

    func testLastChapterHasEndStateWithoutDiscardingImages() {
        let app = launch()
        app.buttons["reader.directory"].tap()
        XCTAssertTrue(app.tables.cells["第6话"].waitForExistence(timeout: 5)); app.tables.cells["第6话"].tap()
        expectation(for: NSPredicate(format: "value CONTAINS '第6话'"), evaluatedWith: app.collectionViews["reader.pages"])
        waitForExpectations(timeout: 10)
        let footer = reachFooter(app)
        XCTAssertEqual(footer.label, "已到最后一章")
        XCTAssertFalse(footer.isEnabled)
        XCTAssertTrue(app.images["reader.image"].firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testStripEdgeTapsAndHorizontalSwipeDoNotChangeChapters() {
        let app = launch(), pages = app.collectionViews["reader.pages"]
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        pages.swipeLeft()
        XCTAssertEqual(pages.value as? String, "第1话，第 1 页，共 4 页")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testLargeDirectoryFastScrollOrderAndCurrentChapterKeepTheReaderReturnPath() {
        let app = launch("--matrix-paged-reader", "--matrix-large-directory")
        app.buttons["reader.directory"].tap()
        let rail = app.otherElements["chapter.drawer.fast-scroll"], table = app.tables["chapter.drawer.list"]
        XCTAssertTrue(rail.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(rail.frame.width, 44)
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)).tap()
        XCTAssertTrue(table.cells["第200话"].isHittable)
        app.buttons["chapter.drawer.order"].tap()
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        XCTAssertTrue(table.cells["第200话"].isHittable); table.cells["第200话"].tap()
        let pages = app.collectionViews["reader.pages"]
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS '第200话'"), object: pages)
        XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: 15), .completed)
        XCTAssertTrue(app.images["reader.image"].firstMatch.exists)
        revealControls(app); app.buttons["reader.directory"].tap()
        XCTAssertEqual(app.buttons["chapter.drawer.order"].label, "倒序")
        XCTAssertTrue(table.cells["第200话"].waitForExistence(timeout: 5)); XCTAssertTrue(table.cells["第200话"].isSelected)
        let currentVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: table.cells["第200话"])
        XCTAssertEqual(XCTWaiter.wait(for: [currentVisible], timeout: 5), .completed)
        XCTAssertTrue(table.cells["第200话"].isHittable)
        app.buttons["chapter.drawer.dismiss"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue((pages.value as? String)?.contains("第200话") == true)
        revealControls(app); app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.buttons["detail.directory"].tap()
        XCTAssertTrue(app.tables["chapter.list"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["chapter.list.order"].label, "倒序")
        let selectedInDetail = app.tables["chapter.list"].cells.containing(.staticText, identifier: "第200话").firstMatch
        let detailVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: selectedInDetail)
        XCTAssertEqual(XCTWaiter.wait(for: [detailVisible], timeout: 5), .completed)
        app.buttons["chapter.list.close"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10)); enterReader(app)
        XCTAssertTrue((pages.value as? String)?.contains("第200话") == true)
        revealControls(app); app.buttons["reader.directory"].tap()
        XCTAssertEqual(app.buttons["chapter.drawer.order"].label, "倒序")
        let restoredVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: table.cells["第200话"])
        XCTAssertEqual(XCTWaiter.wait(for: [restoredVisible], timeout: 5), .completed)
        XCTAssertTrue(table.cells["第200话"].isSelected)
    }

    func testRotationKeepsChapterAndLocalImageAfterContinuousAppend() {
        let app = launch()
        scrollToChapter("第2话", in: app); revealControls(app)
        app.sliders["reader.seek"].adjust(toNormalizedSliderPosition: 0.4)
        let pages = app.collectionViews["reader.pages"]
        let saved = pages.value as? String
        XCTAssertTrue(saved?.contains("第2话") == true)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertGreaterThan(pages.frame.width, pages.frame.height)
        XCTAssertEqual(pages.value as? String, saved, "Rotation must restore the captured chapter, not whichever chapter temporarily occupies the old pixel offset")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertLessThan(pages.frame.width, pages.frame.height)
        XCTAssertEqual(pages.value as? String, saved)
    }

    private func launchCorruptDownload(nextChapter: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-reader-original", "--matrix-download-network", "--light-mode",
                               nextChapter ? "--matrix-corrupt-next-download" : "--matrix-corrupt-first-download"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        app.tables.cells.containing(.staticText, identifier: "下载中心").firstMatch.tap()
        let tasks = app.tables["download.tasks"]
        XCTAssertTrue(tasks.buttons["阅读"].firstMatch.waitForExistence(timeout: 15), "Wait for the real corrupted files and persisted completed task")
        if nextChapter {
            app.navigationBars.buttons.firstMatch.tap(); app.tabBars.buttons["书架"].tap(); enterReader(app)
        } else { tasks.buttons["阅读"].firstMatch.tap() }
        return app
    }

    private func repairAndReturnToReader(_ app: XCUIApplication) {
        let tasks = app.tables["download.tasks"]
        XCTAssertTrue(tasks.waitForExistence(timeout: 5))
        let close = app.navigationBars.buttons["download.reader.close"]
        XCTAssertTrue(close.isHittable)
        let network = app.navigationBars.buttons.matching(NSPredicate(format: "label == '仅 Wi-Fi' OR label == '全网络'")).firstMatch
        network.tap(); app.alerts["下载网络设置"].buttons["确定"].tap()
        XCTAssertTrue(close.isHittable, "Changing network controls must retain the independent return action")
        let status = tasks.staticTexts["download.task.status"].firstMatch
        guard let generation = status.value as? String else { XCTFail("The persisted task generation must be observable"); return }
        tasks.cells.firstMatch.press(forDuration: 1)
        app.buttons["重新下载此章"].tap()
        let confirmation = app.alerts["删除此章的下载文件？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.buttons["重新下载此章"].tap()
        expectation(for: NSPredicate(format: "value BEGINSWITH %@ AND value != %@", "COMPLETED;", generation), evaluatedWith: status)
        waitForExpectations(timeout: 15)
        close.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: tasks)
        waitForExpectations(timeout: 5)
    }

    func testCorruptCurrentChapterReturnsAfterRepairAndUnrepairedReturnKeepsFailure() {
        let app = launchCorruptDownload(nextChapter: false)
        let error = app.buttons["reader.load.status"]
        expectation(for: NSPredicate(format: "label CONTAINS '损坏' AND label CONTAINS '下载中心'"), evaluatedWith: error)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.images["reader.image"].exists)
        error.tap()
        let close = app.navigationBars.buttons["download.reader.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        expectation(for: NSPredicate(format: "label CONTAINS '损坏' AND hittable == true"), evaluatedWith: error)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.images["reader.image"].exists, "Dismissal alone must not mark damaged pixels as repaired")
        error.tap(); repairAndReturnToReader(app)
        expectation(for: NSPredicate(format: "value CONTAINS ':384x384'"), evaluatedWith: app.images["reader.image"].firstMatch)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(error.isHittable)
        XCTAssertTrue((app.collectionViews["reader.pages"].value as? String ?? "").contains("第1话"))
    }

    func testCorruptNextChapterRepairReturnsToContinuousReadingWithoutReloadingFirstChapter() {
        let app = launchCorruptDownload(nextChapter: true)
        let footer = reachFooter(app)
        XCTAssertTrue(footer.label.contains("损坏")); XCTAssertTrue(footer.isHittable)
        XCTAssertTrue(app.images["reader.image"].firstMatch.exists)
        footer.tap(); repairAndReturnToReader(app)
        scrollToChapter("第2话", in: app)
        expectation(for: NSPredicate(format: "value CONTAINS ':384x384'"), evaluatedWith: app.images["reader.image"].firstMatch)
        waitForExpectations(timeout: 15)
        XCTAssertTrue((app.collectionViews["reader.pages"].value as? String ?? "").contains("共 4 页"))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier == 'reader.continuation' AND label CONTAINS '损坏'")).firstMatch.exists)
    }
}
