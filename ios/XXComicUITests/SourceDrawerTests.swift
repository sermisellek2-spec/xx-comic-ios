import XCTest

final class SourceDrawerTests: ParityUITestCase {
    func testGlobalSearchWithoutResultsShowsEmptyFeedbackAndNoSourceTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["发现"].tap()
        app.buttons["discover.search.mode"].tap()
        let search = app.descendants(matching: .any)["discover.search"]
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
        let search = app.descendants(matching: .any)["discover.search"]
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
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.label, original)
        source.tap()
        let confirmedCandidate = app.buttons["filter.source.bbyin"]
        revealSource(confirmedCandidate, in: app)
        confirmedCandidate.tap()
        app.buttons["filter.confirm"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains("比卡漫画"))
    }
    private func revealSource(_ source: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["filter.options"]
        for _ in 0..<12 {
            if source.isHittable { break }
            let target = source.frame, viewport = scroll.frame
            let visible = viewport.insetBy(dx: 0, dy: 8)
            if target.maxY > visible.maxY {
                let distance = min(target.maxY - visible.maxY + 12, viewport.height * 0.5)
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                            withVelocity: .slow, thenHoldForDuration: 0.15)
            } else if target.minY < visible.minY {
                let distance = min(visible.minY - target.minY + 12, viewport.height * 0.5)
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                            withVelocity: .slow, thenHoldForDuration: 0.15)
            } else {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in source.isHittable }, object: source)
                _ = XCTWaiter.wait(for: [ready], timeout: 1)
            }
        }
        if !source.isHittable {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "failure-source-grid-accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let image = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
            image.name = "failure-source-grid"; image.lifetime = .keepAlways; add(image)
        }
        XCTAssertTrue(source.isHittable, "The selected source must be reachable through the actual source grid")
    }
}
