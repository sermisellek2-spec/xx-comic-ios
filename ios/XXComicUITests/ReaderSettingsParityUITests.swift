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
        XCTAssertTrue(app.buttons["reader.layout.2"].exists)
        XCTAssertFalse(app.staticTexts["翻页方式"].exists)
    }
    private func page(_ number: Int, chapter: Int = 1, in app: XCUIApplication) {
        let pages = app.collectionViews["reader.pages"]
        let expected = "第\(chapter)话，第 \(number) 页，共 4 页"
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: pages)
        let result = XCTWaiter.wait(for: [reached], timeout: 10)
        if result != .completed {
            let attachment = XCTAttachment(string: pages.label)
            attachment.name = "reader-transition-expected-chapter-\(chapter)-page-\(number)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(pages.value as? String, expected)
        XCTAssertTrue(app.images.matching(identifier: "reader.image").allElementsBoundByIndex.contains {
            $0.isHittable && ($0.value as? String)?.contains(":384x384") == true
        }, "当前逻辑页必须显示实际原图像素")
    }
    private func controls(_ visible: Bool, in app: XCUIApplication) {
        let button = app.buttons["reader.settings"]
        if (button.exists && button.isHittable) != visible {
            app.collectionViews["reader.pages"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (button.exists && button.isHittable) == visible
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
    }
    func testActualPinchAndZoomedPanDoNotTurnThePageAndTurningResumesAfterZoomReset() {
        let app = launch(); app.buttons["reader.layout.1"].tap(); app.buttons["reader.settings.close"].tap(); page(1, in: app)
        controls(false, in: app)
        let pages = app.collectionViews["reader.pages"], image = app.images["reader.image"].firstMatch
        let width = image.frame.width
        image.pinch(withScale: 2, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in image.frame.width > width * 1.2 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
        pages.swipeLeft(); page(1, in: app)
        image.pinch(withScale: 0.25, velocity: -1)
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(image.frame.width - width) <= 1 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 5), .completed)
        pages.swipeLeft(); page(2, in: app)
    }
    func testMangaTapsModeSwitchAndRelaunchPreserveTheCurrentLogicalPage() {
        let app = launch()
        app.buttons["reader.layout.2"].tap()
        XCTAssertTrue(app.buttons["reader.layout.2"].isSelected)
        app.buttons["reader.settings.close"].tap(); page(1, in: app)
        controls(false, in: app)
        let pages = app.collectionViews["reader.pages"]
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap(); page(2, in: app)
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); page(1, in: app)
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap(); page(2, in: app)
        controls(true, in: app)
        app.buttons["reader.settings"].tap(); app.buttons["reader.layout.1"].tap(); app.buttons["reader.settings.close"].tap()
        page(2, in: app); controls(false, in: app)
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); page(3, in: app)
        controls(true, in: app)
        app.buttons["reader.settings"].tap(); app.buttons["reader.layout.0"].tap(); app.buttons["reader.settings.close"].tap(); page(3, in: app)
        app.buttons["reader.settings"].tap(); app.buttons["reader.layout.2"].tap(); app.buttons["reader.settings.close"].tap(); page(3, in: app)
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); open(app)
        XCTAssertTrue(app.buttons["reader.layout.2"].isSelected)
        XCTAssertFalse(app.staticTexts["左右手模式"].exists)
        app.buttons["reader.settings.close"].tap(); page(3, in: app)
    }
    func testArchivedButtonPreferenceKeepsNormalAndMangaTurnsUsableAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-reader-original", "--matrix-legacy-button-reader", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); open(app)
        XCTAssertTrue(app.buttons["reader.layout.1"].isSelected)
        XCTAssertFalse(app.staticTexts["翻页方式"].exists)
        app.buttons["reader.settings.close"].tap(); page(1, in: app)
        controls(false, in: app)
        let pages = app.collectionViews["reader.pages"]
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); page(2, in: app)
        pages.swipeLeft(); page(3, in: app)
        controls(true, in: app)
        app.buttons["reader.settings"].tap(); app.buttons["reader.layout.2"].tap(); app.buttons["reader.settings.close"].tap()
        page(3, in: app); controls(false, in: app)
        pages.swipeRight(); page(4, in: app)
        pages.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); page(3, in: app)
        controls(true, in: app); app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); open(app)
        XCTAssertTrue(app.buttons["reader.layout.2"].isSelected)
        XCTAssertFalse(app.staticTexts["翻页方式"].exists)
        app.buttons["reader.settings.close"].tap(); page(3, in: app)
        controls(false, in: app); pages.swipeRight(); page(4, in: app)
    }
    func testDefaultMangaSwipeAdvancesOnceAndCrossesToTheNextLogicalChapter() {
        let app = launch()
        app.buttons["reader.layout.2"].tap(); app.buttons["reader.settings.close"].tap(); page(1, in: app)
        let pages = app.collectionViews["reader.pages"]
        pages.swipeRight(); page(2, in: app)
        pages.swipeLeft(); page(1, in: app)
        for next in 2...4 { pages.swipeRight(); page(next, in: app) }
        pages.swipeRight(); page(1, chapter: 2, in: app)
        controls(true, in: app)
        app.buttons["reader.settings"].tap(); app.buttons["reader.layout.1"].tap(); app.buttons["reader.settings.close"].tap()
        page(1, chapter: 2, in: app)
        pages.swipeLeft(); page(2, chapter: 2, in: app)
    }
    func testMangaRotationPreservesTheLogicalPageAndChapter() {
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        app.buttons["reader.layout.2"].tap(); app.buttons["reader.settings.close"].tap(); page(1, in: app)
        let pages = app.collectionViews["reader.pages"]
        pages.swipeRight(); page(2, in: app)
        pages.swipeRight(); page(3, in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        page(3, in: app)
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.height > frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
        page(3, in: app)
        pages.swipeRight(); page(4, in: app)
    }
    func testStripImageOffsetSurvivesNormalMangaAndPagedRelaunch() {
        let app = launch()
        XCTAssertTrue(app.buttons["reader.layout.0"].isSelected)
        app.buttons["reader.settings.close"].tap()
        controls(false, in: app)
        let pages = app.collectionViews["reader.pages"]
        let start = pages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = pages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        func topImageFrame() -> CGRect? {
            app.images.matching(identifier: "reader.image").allElementsBoundByIndex
                .map(\.frame).filter { $0.height > 0 && $0.maxY > pages.frame.minY + 20 && $0.minY < pages.frame.maxY }
                .sorted { $0.minY < $1.minY }.first
        }
        guard let original = topImageFrame() else { XCTFail("卷轴应显示真实图片"); return }
        XCTAssertLessThan(original.minY, pages.frame.minY - 40, "先真实滚到图内，不能只验证页码")
        let value = pages.value as? String
        for mode in [1, 2] {
            controls(true, in: app)
            app.buttons["reader.settings"].tap(); app.buttons["reader.layout.\(mode)"].tap()
            app.buttons["reader.settings.close"].tap()
            XCTAssertEqual(pages.value as? String, value)
        }
        controls(true, in: app); app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); open(app)
        XCTAssertTrue(app.buttons["reader.layout.2"].isSelected)
        app.buttons["reader.layout.0"].tap(); app.buttons["reader.settings.close"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let frame = topImageFrame() else { return false }
            return (pages.value as? String) == value && abs(frame.minY - original.minY) <= 1 && abs(frame.height - original.height) <= 1
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
        XCTAssertEqual(pages.value as? String, value)
        guard let resumed = topImageFrame() else { XCTFail("模式恢复后应显示原图"); return }
        XCTAssertEqual(resumed.minY, original.minY, accuracy: 1)
        XCTAssertEqual(resumed.height, original.height, accuracy: 1)
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
