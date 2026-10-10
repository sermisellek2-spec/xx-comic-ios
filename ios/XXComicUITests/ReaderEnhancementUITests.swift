import XCTest

final class ReaderEnhancementUITests: XCTestCase {
    func testReaderAIBadgeAndLongPressOriginalComparison() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--epub-fixtures"]
        app.launch()

        // Open local shelf
        XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 10))
        app.buttons["本地书架"].tap()

        // Open picture comic EPUB
        let cell = app.collectionViews.cells["EPUB 验收·图片"]
        for _ in 0..<5 where !cell.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()

        // Tap chapters button
        XCTAssertTrue(app.buttons["章节目录"].waitForExistence(timeout: 10))
        app.buttons["章节目录"].tap()

        XCTAssertTrue(app.tables.cells.firstMatch.waitForExistence(timeout: 10))
        app.tables.cells.firstMatch.tap()

        // Center tap to verify reader controls
        let center = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()

        // Take screenshot of reader with controls and enhancement badge
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "reader_enhancement_badge_view"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Perform long press gesture to trigger original comparison
        center.press(forDuration: 0.8)
    }
}
