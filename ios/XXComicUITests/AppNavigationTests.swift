import XCTest
import UIKit

final class AppNavigationTests: ParityUITestCase {
    func testInstalledApplicationIconAppearsOnHomeScreenAndOpensTheApp() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString; app.launch()
        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["XX Comic"].firstMatch
        for _ in 0..<4 where !icon.isHittable { springboard.swipeLeft() }
        XCTAssertTrue(icon.waitForExistence(timeout: 5)); XCTAssertTrue(icon.isHittable)
        XCTAssertGreaterThanOrEqual(icon.frame.width, 44)
        let stem = (UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone") + "_portrait_light_app_icon_home"
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = stem; attachment.lifetime = .keepAlways; add(attachment)
        let frame = icon.frame
        let record: [String: Any] = ["scene": stem, "bundleID": "com.xxcomic.ios", "displayName": icon.label,
                                   "iconFrame": [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
                                   "screenScale": Double(UIScreen.main.scale), "capturedAtUTC": ISO8601DateFormatter().string(from: Date())]
        do {
            let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
            metadata.name = "provenance-" + stem; metadata.lifetime = .keepAlways; add(metadata)
        } catch { XCTFail("Cannot retain actual installed icon provenance: \(error)") }
        icon.tap()
        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 5))
    }

    func testNavigationAndReaderPreferencesPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        func openReadingSettings() {
            app.buttons["我的书架"].tap()
            let comic = app.collectionViews.cells["电锯人"]
            XCTAssertTrue(comic.waitForExistence(timeout: 5)); comic.tap()
            app.buttons["detail.read"].tap()
            let settings = app.buttons["reader.settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].exists)
        XCTAssertTrue(app.buttons["我的书架"].isHittable)
        XCTAssertTrue(app.buttons["本地书架"].isHittable)
        app.buttons["本地书架"].tap()
        XCTAssertTrue(app.buttons["我的书架"].isHittable)
        XCTAssertTrue(app.buttons["本地书架"].isSelected)
        openReadingSettings()
        let toggle = app.switches["reader.disable.page.animation"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        toggle.tap()
        let changed = toggle.value as? String
        XCTAssertNotEqual(original, changed)
        app.terminate()
        app.launch()
        openReadingSettings()
        XCTAssertEqual(app.switches["reader.disable.page.animation"].value as? String, changed)
        app.switches["reader.disable.page.animation"].tap()
    }
}
