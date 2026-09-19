import XCTest

final class SourceDrawerTests: XCTestCase {
    func testCategoryOnlySourceShowsUnsupportedSearchAndIsAbsentFromGlobalTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["发现"].tap()
        app.buttons["discover.source"].tap()
        let source = app.buttons["filter.source.cuimh"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        app.buttons["filter.confirm"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("测试\n")
        XCTAssertTrue(app.buttons["催漫画暂不支持搜索"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["全站"].tap()
        XCTAssertTrue(app.buttons["discover.global.baozimh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discover.global.cuimh"].exists)
        XCTAssertFalse(app.buttons["discover.global.liumanhua"].exists)
    }

    func testSourceDraftIsDiscardedOnCloseAndAppliedOnConfirm() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["发现"].tap()
        let source = app.buttons["discover.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        let original = source.label
        source.tap()
        let candidate = app.buttons["filter.source.bbyin"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        candidate.tap()
        app.buttons["filter.close"].tap()
        XCTAssertEqual(source.label, original)
        source.tap()
        app.buttons["filter.source.bbyin"].tap()
        app.buttons["filter.confirm"].tap()
        XCTAssertTrue(source.label.contains("比卡漫画"))
    }
}
