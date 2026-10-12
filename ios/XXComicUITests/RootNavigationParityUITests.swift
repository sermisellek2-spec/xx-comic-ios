import XCTest

final class RootNavigationParityUITests: ParityUITestCase {
    private func exercise(landscape: Bool, dark: Bool) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", dark ? "--dark-mode" : "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        let bar = app.tabBars["navigation.tabs"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertEqual(bar.buttons.count, 3)
        for title in ["书架", "发现", "设置"] {
            XCTAssertTrue(bar.buttons[title].isHittable)
            XCTAssertGreaterThanOrEqual(bar.buttons[title].frame.height, 44)
        }
        bar.buttons["发现"].tap()
        XCTAssertTrue(bar.buttons["发现"].isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["discover.search"].waitForExistence(timeout: 5))
        bar.buttons["设置"].tap()
        XCTAssertTrue(bar.buttons["设置"].isSelected)
        XCTAssertTrue(app.tables.cells["settings.theme"].waitForExistence(timeout: 5))
        bar.buttons["书架"].tap(); app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 5)); comic.tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        XCTAssertFalse(bar.exists, "详情内容使用完整窗口，根底栏不能遮住阅读入口")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.buttons["书架"].isSelected)
        XCTAssertTrue(comic.waitForExistence(timeout: 5))
        let frame = app.windows.firstMatch.frame
        XCTAssertEqual(frame.width > frame.height, landscape)
        XCTAssertEqual(bar.frame.maxY, frame.maxY, accuracy: 1)
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = "root-tabs-\(landscape ? "landscape" : "portrait")-\(dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPortraitLightTabsAndDetailReturn() { exercise(landscape: false, dark: false) }
    func testPortraitDarkTabsAndDetailReturn() { exercise(landscape: false, dark: true) }
    func testLandscapeLightTabsAndDetailReturn() { exercise(landscape: true, dark: false) }
    func testLandscapeDarkTabsAndDetailReturn() { exercise(landscape: true, dark: true) }
}
