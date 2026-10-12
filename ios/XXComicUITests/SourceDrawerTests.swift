import XCTest

final class SourceDrawerTests: ParityUITestCase {
    func testGlobalSearchWithoutResultsShowsEmptyFeedbackAndNoSourceTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["发现"].tap()
        app.buttons["discover.search.mode"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("未匹配的验收关键词\n")
        let empty = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "没有找到漫画")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertEqual(app.collectionViews.cells.count, 0)
        for id in ["mh160", "copy4000", "gmh", "cuimh", "liumanhua"] {
            XCTAssertFalse(app.buttons["discover.global." + id].exists)
        }
    }
    func testCategoryOnlySourceShowsUnsupportedSearchAndIsAbsentFromGlobalTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["已经到底了"].waitForExistence(timeout: 2), "A short first page must not start paging before the user scrolls")
        app.buttons["discover.source"].tap()
        let source = app.buttons["filter.source.cuimh"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        revealSource(source, in: app)
        source.tap()
        app.buttons["filter.confirm"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        // Android exposes only sources that returned results. Use a title in
        // the shared fixture so the supported-source assertions have results.
        search.typeText("电锯人\n")
        XCTAssertTrue(app.buttons["催漫画暂不支持搜索"].waitForExistence(timeout: 5))
        app.buttons["discover.search.mode"].tap()
        XCTAssertTrue(app.buttons["discover.global.mh160"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discover.global.baozimh"].exists)
        XCTAssertFalse(app.buttons["discover.global.cuimh"].exists)
        XCTAssertFalse(app.buttons["discover.global.liumanhua"].exists)
    }

    func testSourceDraftIsDiscardedOnCloseAndAppliedOnConfirm() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["发现"].tap()
        let source = app.buttons["discover.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        let original = source.label
        source.tap()
        let candidate = app.buttons["filter.source.bbyin"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        revealSource(candidate, in: app)
        candidate.tap()
        app.buttons["filter.close"].tap()
        XCTAssertEqual(source.label, original)
        source.tap()
        let confirmedCandidate = app.buttons["filter.source.bbyin"]
        revealSource(confirmedCandidate, in: app)
        confirmedCandidate.tap()
        app.buttons["filter.confirm"].tap()
        XCTAssertTrue(source.label.contains("比卡漫画"))
    }
    private func revealSource(_ source: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !source.isHittable { app.scrollViews["filter.options"].swipeUp() }
        XCTAssertTrue(source.isHittable, "The selected source must be reachable through the actual source grid")
    }
}
