import XCTest
import UIKit

final class VisualMatrixUITests: ParityUITestCase {
    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let frame = XCUIApplication().windows.firstMatch.frame
        let record: [String: Any] = [
            "fixtureID": ParityFixtureIdentity.fixtureID,
            "metadataSHA256": ParityFixtureIdentity.metadataSHA256,
            "imageSHA256": ParityFixtureIdentity.imageSHA256,
            "scene": name,
            "appFrame": ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)],
            "screenScale": Double(UIScreen.main.scale),
            "preferredContentSizeCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "capturedAtUTC": ISO8601DateFormatter().string(from: Date()),
            "steps": "VisualMatrixUITests production navigation with explicitly isolated Debug fixture"
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            metadata.name = "provenance-" + name; metadata.lifetime = .keepAlways; add(metadata)
        } catch { XCTFail("Cannot retain actual screenshot provenance: \(error)") }
    }
    private func exercise(landscape: Bool, dark: Bool) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures", "--epub-fixtures", dark ? "--dark-mode" : "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10))
        let prefix = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let stem = "\(prefix)_\(landscape ? "landscape" : "portrait")_\(dark ? "dark" : "light")_"
        let frame = app.windows.firstMatch.frame
        XCTAssertEqual(frame.width > frame.height, landscape)
        app.buttons["我的书架"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
        capture(stem + "bookshelf_online")
        app.buttons["本地书架"].tap()
        XCTAssertTrue(app.collectionViews.cells["EPUB 验收·图片"].waitForExistence(timeout: 5))
        capture(stem + "bookshelf_local")
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
        capture(stem + "discover")
        app.buttons["discover.source"].tap()
        XCTAssertTrue(app.buttons["filter.close"].waitForExistence(timeout: 5))
        capture(stem + "source_drawer")
        app.buttons["filter.close"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("电锯人\n")
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
        capture(stem + "search_results")
        app.tabBars.buttons["书架"].tap(); app.buttons["我的书架"].tap()
        app.collectionViews.cells["电锯人"].tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.title"].label, "电锯人")
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.read"].isHittable)
        XCTAssertLessThanOrEqual(app.buttons["detail.favorite"].frame.height, 48)
        capture(stem + "detail")
        app.buttons["detail.switch-source"].tap()
        XCTAssertTrue(app.tables["source-switch.candidates"].cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["source-switch.cancel"].waitForExistence(timeout: 5))
        capture(stem + "source_switch")
        app.buttons["source-switch.cancel"].tap()
        app.buttons["detail.read"].tap()
        let image = app.images["reader.image"].firstMatch
        expectation(for: NSPredicate(format: "value BEGINSWITH 'neural:'"), evaluatedWith: image)
        waitForExpectations(timeout: 30)
        capture(stem + "reader")
        app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.switches["reader.disable.page.animation"].waitForExistence(timeout: 5))
        capture(stem + "reading_settings")
        app.buttons["reader.settings.close"].tap()
        app.buttons["目录"].tap()
        XCTAssertTrue(app.tables.cells.firstMatch.waitForExistence(timeout: 5))
        capture(stem + "reader_directory")
        app.tables.cells.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        capture(stem + "settings")
        for (label, name) in [("下载中心", "downloads"), ("缓存清理", "cache_cleanup")] {
            let item = app.tables.staticTexts[label]
            XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
            capture(stem + name)
            app.navigationBars.buttons.firstMatch.tap()
        }
    }
    func testVisualMatrixPortraitLight() { exercise(landscape: false, dark: false) }
    func testVisualMatrixPortraitDark() { exercise(landscape: false, dark: true) }
    func testVisualMatrixLandscapeLight() { exercise(landscape: true, dark: false) }
    func testVisualMatrixLandscapeDark() { exercise(landscape: true, dark: true) }

    // Matches the empty library / 51 sources / disabled statistics Android reference.
    // Attachments become comparison evidence only after this actually runs on Apple.
    private func settingsReference(landscape: Bool, dark: Bool) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures", "--matrix-empty-library", "--matrix-disabled-statistics", "--matrix-reference-automatic-theme", dark ? "--dark-mode" : "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        // Match the reference's empty cache through the actual cleanup UI.
        // URLCache can otherwise retain responses from earlier UI-test sessions.
        app.tables.cells["settings.cache"].tap()
        app.buttons["确认清理"].tap()
        app.buttons["立即清理"].tap()
        let cleared = app.staticTexts["缓存已清理，收藏与本地漫画已保留"]
        XCTAssertTrue(cleared.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["确认清理"].isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tables.cells["settings.cache"].staticTexts["0 B"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tables.cells.count, 11)
        XCTAssertTrue(app.tables.cells["settings.theme"].staticTexts["自动"].exists)
        XCTAssertTrue(app.tables.cells["settings.sources"].staticTexts["50 个开启"].exists)
        XCTAssertTrue(app.tables.cells["settings.history"].staticTexts["0 条"].exists)
        let frame = app.windows.firstMatch.frame
        XCTAssertEqual(frame.width > frame.height, landscape)
        let idiom = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        capture("\(idiom)_\(landscape ? "landscape" : "portrait")_\(dark ? "dark" : "light")_settings_reference_empty")
    }
    func testSettingsReferencePortraitLight() { settingsReference(landscape: false, dark: false) }
    func testSettingsReferencePortraitDark() { settingsReference(landscape: false, dark: true) }
    func testSettingsReferenceLandscapeLight() { settingsReference(landscape: true, dark: false) }
    func testSettingsReferenceLandscapeDark() { settingsReference(landscape: true, dark: true) }
}
