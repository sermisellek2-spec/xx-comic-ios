import XCTest

final class VisualMatrixUITests: XCTestCase {

    private func captureScreen(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // Save directly to /tmp/matrix_screenshots for script extraction
        let outputDir = URL(fileURLWithPath: "/tmp/matrix_screenshots")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let filePath = outputDir.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: filePath)
        print("[VisualMatrix] Captured screenshot: \(name).png (\(screenshot.pngRepresentation.count) bytes)")
    }

    private func devicePrefix() -> String {
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    func testVisualMatrixPortraitLight() {
        let prefix = devicePrefix()
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"]
        app.launch()

        // 1. Bookshelf - Online
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10))
        captureScreen(named: "\(prefix)_portrait_light_bookshelf_online")

        // Bookshelf - Local
        if app.buttons["本地书架"].waitForExistence(timeout: 5) {
            app.buttons["本地书架"].tap()
            captureScreen(named: "\(prefix)_portrait_light_bookshelf_local")
            if app.buttons["我的书架"].waitForExistence(timeout: 3) {
                app.buttons["我的书架"].tap()
            }
        }

        // 2. Discover
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.buttons["discover.source"].waitForExistence(timeout: 5))
        captureScreen(named: "\(prefix)_portrait_light_discover")

        // Source Drawer
        app.buttons["discover.source"].tap()
        captureScreen(named: "\(prefix)_portrait_light_source_drawer")
        if app.buttons["filter.close"].exists {
            app.buttons["filter.close"].tap()
        }

        // Search test
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("电锯人\n")
            captureScreen(named: "\(prefix)_portrait_light_search_results")
        }

        // 3. Detail Page
        app.tabBars.buttons["书架"].tap()
        let firstCard = app.collectionViews.cells.firstMatch
        if firstCard.waitForExistence(timeout: 5) {
            firstCard.tap()
            captureScreen(named: "\(prefix)_portrait_light_detail")

            // Source Switch Sheet
            if app.buttons["换源"].waitForExistence(timeout: 3) {
                app.buttons["换源"].tap()
                captureScreen(named: "\(prefix)_portrait_light_source_switch")
                app.buttons["取消"].tap()
            }

            // Return to bookshelf
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
            }
        }

        // 4. Settings and Subpages
        _ = app.tabBars.buttons["设置"].waitForExistence(timeout: 5)
        app.tabBars.buttons["设置"].tap()
        captureScreen(named: "\(prefix)_portrait_light_settings")

        // Downloads
        if app.tables.staticTexts["下载中心"].waitForExistence(timeout: 3) {
            app.tables.staticTexts["下载中心"].tap()
            captureScreen(named: "\(prefix)_portrait_light_downloads")
            app.navigationBars.buttons.firstMatch.tap()
        }

        // Reading preferences
        if app.tables.staticTexts["阅读设置"].waitForExistence(timeout: 3) {
            app.tables.staticTexts["阅读设置"].tap()
            captureScreen(named: "\(prefix)_portrait_light_reading_settings")
            app.navigationBars.buttons.firstMatch.tap()
        }

        // Cache cleanup
        if app.tables.staticTexts["缓存清理"].waitForExistence(timeout: 3) {
            app.tables.staticTexts["缓存清理"].tap()
            captureScreen(named: "\(prefix)_portrait_light_cache_cleanup")
            app.navigationBars.buttons.firstMatch.tap()
        }

        // About
        if app.tables.staticTexts["关于与更新"].waitForExistence(timeout: 3) {
            app.tables.staticTexts["关于与更新"].tap()
            captureScreen(named: "\(prefix)_portrait_light_about")
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func testVisualMatrixPortraitDark() {
        let prefix = devicePrefix()
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--dark-mode"]
        app.launch()

        // Bookshelf Dark
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10))
        captureScreen(named: "\(prefix)_portrait_dark_bookshelf")

        // Discover Dark
        app.tabBars.buttons["发现"].tap()
        captureScreen(named: "\(prefix)_portrait_dark_discover")

        // Settings Dark
        app.tabBars.buttons["设置"].tap()
        captureScreen(named: "\(prefix)_portrait_dark_settings")
    }

    func testVisualMatrixLandscapeLight() {
        let prefix = devicePrefix()
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"]
        app.launch()

        // Bookshelf Landscape Light
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10))
        captureScreen(named: "\(prefix)_landscape_light_bookshelf")

        // Discover Landscape Light
        app.tabBars.buttons["发现"].tap()
        captureScreen(named: "\(prefix)_landscape_light_discover")

        // Settings Landscape Light
        app.tabBars.buttons["设置"].tap()
        captureScreen(named: "\(prefix)_landscape_light_settings")

        // Reset orientation
        XCUIDevice.shared.orientation = .portrait
    }

    func testVisualMatrixLandscapeDark() {
        let prefix = devicePrefix()
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--dark-mode"]
        app.launch()

        // Bookshelf Landscape Dark
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10))
        captureScreen(named: "\(prefix)_landscape_dark_bookshelf")

        // Discover Landscape Dark
        app.tabBars.buttons["发现"].tap()
        captureScreen(named: "\(prefix)_landscape_dark_discover")

        // Settings Landscape Dark
        app.tabBars.buttons["设置"].tap()
        captureScreen(named: "\(prefix)_landscape_dark_settings")

        // Reset orientation
        XCUIDevice.shared.orientation = .portrait
    }
}
