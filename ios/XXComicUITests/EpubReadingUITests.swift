import XCTest
import UIKit

/// These are executable Apple UI scenarios, not source-code assertions. Run with an iOS simulator.
final class EpubReadingUITests: ParityUITestCase {
    // One sandbox per scenario; relaunching the same app preserves its saved state.
    private let sessionID = UUID().uuidString
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--epub-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = sessionID
        app.launch()
        XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 20)); app.buttons["本地书架"].tap()
        return app
    }
    private func open(_ name: String, app: XCUIApplication) {
        let cell = app.collectionViews.cells["EPUB 验收·" + name]
        for _ in 0..<5 where !cell.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(cell.waitForExistence(timeout: 15)); cell.tap()
        XCTAssertTrue(app.buttons["章节目录"].waitForExistence(timeout: 10)); app.buttons["章节目录"].tap()
        if name == "图片" {
            XCTAssertTrue(app.tables.cells.firstMatch.waitForExistence(timeout: 10)); app.tables.cells.firstMatch.tap()
        } else {
            XCTAssertTrue(app.tables.staticTexts["第一章"].waitForExistence(timeout: 10)); app.tables.staticTexts["第一章"].tap()
        }
    }
    private func ready(_ app: XCUIApplication) {
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["epub.state"])
        waitForExpectations(timeout: 15)
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }

    func testLongBodyWithoutIDsResumesByPercentage() {
        let app = launch(); open("无锚点", app: app); ready(app)
        app.sliders["epub.progress"].adjust(toNormalizedSliderPosition: 0.65)
        let nearSavedPosition = NSPredicate { _, _ in
            guard let value = app.sliders["epub.progress"].value as? String,
                  let number = Double(value.replacingOccurrences(of: "%", with: "")) else { return false }
            return (60...70).contains(number)
        }
        expectation(for: nearSavedPosition, evaluatedWith: app); waitForExpectations(timeout: 5)
        back(app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '继续阅读'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap(); ready(app)
        expectation(for: nearSavedPosition, evaluatedWith: app); waitForExpectations(timeout: 5)
        XCTAssertFalse(app.webViews.staticTexts["无锚点正文"].isHittable)
    }

    func testEncodedFragmentsReachSameBodyAndCrossSpineTargetsExactlyOnce() {
        let app = launch(); open("编码空锚点", app: app); ready(app)
        let cases = [("同页中文空格", "同页中文目标已到达"), ("同页字面百分号", "同页百分号目标已到达"),
                     ("跨章中文空格", "跨章中文目标已到达"), ("跨章字面百分号", "跨章百分号目标已到达")]
        for (link, target) in cases {
            app.buttons["目录"].tap()
            XCTAssertTrue(app.tables.staticTexts["第一章"].waitForExistence(timeout: 5)); app.tables.staticTexts["第一章"].tap(); ready(app)
            app.sliders["epub.progress"].adjust(toNormalizedSliderPosition: 0)
            let anchorLink = app.webViews.links[link]
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: anchorLink); waitForExpectations(timeout: 5)
            anchorLink.tap()
            let destination = app.webViews.staticTexts[target]
            expectation(for: NSPredicate { _, _ in
                guard let value = app.sliders["epub.progress"].value as? String,
                      let number = Double(value.replacingOccurrences(of: "%", with: "")) else { return false }
                return destination.isHittable && number > 0
            }, evaluatedWith: app); waitForExpectations(timeout: 10)
            if link.hasPrefix("跨章") { XCTAssertEqual(app.staticTexts["epub.section"].value as? String, "第2章，第1节") }
        }
    }

    func testAllSpinesAndRealSecondChapterResumeRoute() {
        let app = launch(); open("文字", app: app); ready(app)
        app.buttons["下一节"].tap(); ready(app)
        XCTAssertTrue(app.webViews.staticTexts["第一章第二节"].exists)
        app.buttons["下一节"].tap(); ready(app)
        XCTAssertEqual(app.staticTexts["epub.section"].value as? String, "第2章，第1节")
        app.sliders["epub.progress"].adjust(toNormalizedSliderPosition: 0.55)
        // Let the independent-world restore and 100 ms reporter finish before leaving.
        expectation(for: NSPredicate { _, _ in
            guard let value = app.sliders["epub.progress"].value as? String,
                  let number = Double(value.replacingOccurrences(of: "%", with: "")) else { return false }
            return number >= 50 && number <= 60
        }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        back(app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '继续阅读'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap(); ready(app)
        XCTAssertEqual(app.staticTexts["epub.section"].value as? String, "第2章，第1节")
        XCTAssertTrue(app.webViews.staticTexts["第二章正文"].exists)
        XCTAssertNotEqual(app.sliders["epub.progress"].value as? String, "0%")
    }

    func testTextSettingsPersistAfterRelaunch() {
        let app = launch(); open("文字", app: app); ready(app)
        app.buttons["排版"].tap()
        XCTAssertTrue(app.buttons["epub.fontSize-Increment"].waitForExistence(timeout: 5))
        let before = app.tables.cells.element(boundBy: 0).staticTexts.firstMatch.label
        let isMaximum = before.contains("32")
        app.buttons[isMaximum ? "epub.fontSize-Decrement" : "epub.fontSize-Increment"].tap()
        let changed = app.tables.cells.element(boundBy: 0).staticTexts.firstMatch.label
        XCTAssertNotEqual(before, changed)
        app.buttons["护眼"].tap(); app.buttons["点击翻页"].tap()
        app.terminate(); app.launch(); app.buttons["本地书架"].tap()
        open("文字", app: app); ready(app); app.buttons["排版"].tap()
        XCTAssertEqual(app.tables.cells.element(boundBy: 0).staticTexts.firstMatch.label, changed)
        XCTAssertTrue(app.buttons["护眼"].isSelected); XCTAssertTrue(app.buttons["点击翻页"].isSelected)
    }

    func testTextSettingsPanelKeepsEveryActionReachableAcrossThemesAndOrientations() {
        defer { XCUIDevice.shared.orientation = .portrait }
        for theme in ["light", "dark"] {
            for (name, orientation) in [("portrait", UIDeviceOrientation.portrait), ("landscape", .landscapeLeft)] {
                XCUIDevice.shared.orientation = orientation
                let app = XCUIApplication()
                app.launchArguments = ["--ui-testing", "--epub-fixtures", "--\(theme)-mode"]
                app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
                app.launch()
                XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 20)); app.buttons["本地书架"].tap()
                open("文字", app: app); ready(app); app.buttons["排版"].tap()
                let panel = app.tables["epub.text.settings"]
                XCTAssertTrue(panel.waitForExistence(timeout: 5)); XCTAssertEqual(panel.cells.count, 4)
                let window = app.frame
                XCTAssertGreaterThanOrEqual(panel.frame.minX, window.minX)
                XCTAssertGreaterThanOrEqual(panel.frame.minY, window.minY)
                XCTAssertLessThanOrEqual(panel.frame.maxX, window.maxX)
                XCTAssertLessThanOrEqual(panel.frame.maxY, window.maxY)
                let increment = app.buttons["epub.fontSize-Increment"]
                XCTAssertTrue(increment.isHittable)
                let before = panel.cells.element(boundBy: 0).staticTexts.firstMatch.label
                increment.tap()
                XCTAssertNotEqual(panel.cells.element(boundBy: 0).staticTexts.firstMatch.label, before)
                for identifier in ["epub.lineHeight.2", "epub.theme.1", "epub.turn.1"] {
                    let button = app.buttons[identifier]
                    for _ in 0..<3 where !button.isHittable { panel.swipeUp() }
                    XCTAssertTrue(button.isHittable); button.tap(); XCTAssertTrue(button.isSelected)
                }
                captureTextSettings(app, theme: theme, orientation: name)
                app.buttons["epub.text.settings.close"].tap(); ready(app)
                XCTAssertFalse(panel.exists)
                app.buttons["排版"].tap()
                XCTAssertTrue(app.buttons["epub.theme.1"].isSelected)
                XCTAssertTrue(app.buttons["epub.turn.1"].isSelected)
                app.buttons["epub.text.settings.close"].tap(); app.terminate()
            }
        }
    }

    private func captureTextSettings(_ app: XCUIApplication, theme: String, orientation: String) {
        let name = "text-settings-\(theme)-\(orientation)"
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        guard let raster = screenshot.image.cgImage else { XCTFail("Missing text-settings raster"); return }
        let frame = app.windows.firstMatch.frame
        let record: [String: Any] = [
            "fixtureID": "epub-fixtures/EPUB 验收·文字",
            "fixtureSource": "ios/XXComic/EpubUITestFixtures.swift at tested revision",
            "scene": name,
            "appFrame": ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)],
            "screenScale": Double(UIScreen.main.scale), "rasterPixelSize": [raster.width, raster.height],
            "screenshotImageSizePT": [Double(screenshot.image.size.width), Double(screenshot.image.size.height)],
            "screenshotImageScale": Double(screenshot.image.scale),
            "screenshotImageOrientation": screenshot.image.imageOrientation.rawValue,
            "preferredContentSizeCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "capturedAtUTC": ISO8601DateFormatter().string(from: Date()),
            "accessibilitySnapshot": app.debugDescription,
            "steps": "本地书架→EPUB 验收·文字→第一章→排版→字号加一→宽松→护眼→点击翻页",
            "comparisonStatus": "Apple运行证据；同内容Android文字面板对照尚未运行"
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            metadata.name = "provenance-" + name; metadata.lifetime = .keepAlways; add(metadata)
        } catch { XCTFail("Cannot retain text-settings screenshot provenance: \(error)") }
    }

    func testMixedSpineRetainsDirectImageAndPureImageUsesComicReader() {
        let app = launch(); open("图文", app: app); ready(app)
        app.buttons["下一节"].tap(); ready(app)
        app.buttons["下一节"].tap(); ready(app)
        XCTAssertTrue(app.webViews.images["正文插图"].exists)
        app.buttons["下一节"].tap(); ready(app)
        XCTAssertTrue(app.webViews.staticTexts["第二章正文"].exists)
        back(app); back(app); open("图片", app: app)
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testPendingScrollRestoreCannotOverwriteNextDocumentPosition() {
        let app = launch(); open("文字", app: app); ready(app)
        XCTAssertEqual(app.staticTexts["epub.section"].value as? String, "第1章，第1节")
        app.sliders["epub.progress"].adjust(toNormalizedSliderPosition: 0.8)
        app.buttons["下一节"].tap()
        ready(app)
        XCTAssertTrue(app.webViews.staticTexts["第一章第二节"].exists)
        XCTAssertEqual(app.sliders["epub.progress"].value as? String, "0%")
        back(app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '继续阅读'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap(); ready(app)
        XCTAssertEqual(app.staticTexts["epub.section"].value as? String, "第1章，第2节")
        XCTAssertEqual(app.sliders["epub.progress"].value as? String, "0%")
    }

    func testWebKitBlocksBookScriptsAndLoadsSameBookCSS() {
        let app = launch(); open("隔离", app: app); ready(app)
        XCTAssertTrue(app.webViews.staticTexts["脚本未执行"].exists)
        XCTAssertTrue(app.webViews.staticTexts["事件未执行"].exists)
        XCTAssertFalse(app.webViews.staticTexts["本书 CSS 未加载"].exists)
        XCTAssertFalse(app.webViews.staticTexts["第二章正文"].exists) // iframe must not render.
        // With book scripts disabled, WebKit exposes this javascript: target as static text.
        XCTAssertFalse(app.webViews.links["不安全链接"].exists)
        XCTAssertTrue(app.webViews.staticTexts["不安全链接"].exists)
        app.webViews.staticTexts["不安全链接"].tap()
        XCTAssertFalse(app.webViews.staticTexts["JS链接执行"].exists)
        app.webViews.links["外部测试链接"].tap()
        XCTAssertTrue(app.alerts["打开外部链接？"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        back(app)
        XCTAssertTrue(app.buttons["章节目录"].waitForExistence(timeout: 5))
    }

    func testOversizedDocumentFailsAndCanSwitchAwayWithoutLateCallbacks() {
        let app = launch(); open("超限", app: app)
        let state = app.buttons["epub.state"]
        expectation(for: NSPredicate(format: "label CONTAINS '上限'"), evaluatedWith: state)
        waitForExpectations(timeout: 15)
        app.buttons["下一节"].tap(); ready(app)
        XCTAssertTrue(app.webViews.staticTexts["第一章第二节"].exists)
        app.buttons["下一节"].tap() // Old callbacks cannot overwrite the new chapter after leaving.
        ready(app); back(app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '继续阅读'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap(); ready(app)
        XCTAssertEqual(app.staticTexts["epub.section"].value as? String, "第2章，第1节")
    }

    func testCrossBookResourceCannotRenderAndImportEntryOpensDocumentPicker() {
        let app = launch(); open("跨书", app: app)
        // The other real book's CSS hides the body if it is loaded; CSP or the scheme handler must refuse it.
        let visible = app.webViews.staticTexts["跨书样式未执行"]
        let failure = app.buttons.matching(identifier: "epub.state").matching(NSPredicate(format: "label CONTAINS %@", "重试")).firstMatch
        // Query the terminal failure state in one snapshot. The loading button
        // can disappear between an `exists` lookup and a separate label lookup.
        expectation(for: NSPredicate { _, _ in visible.exists || failure.exists }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        back(app); back(app)
        app.buttons["本地书架"].tap(); app.buttons["bookshelf.import"].tap(); app.buttons["EPUB 电子书"].tap()
        let cancel = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 5))
    }

    private func launchKindle() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--epub-fixtures", "--kindle-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = sessionID
        app.launch()
        XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 20)); app.buttons["本地书架"].tap()
        return app
    }

    @discardableResult
    private func importKindle(_ kind: String, app: XCUIApplication) -> String {
        app.buttons["本地书架"].tap(); app.buttons["bookshelf.import"].tap()
        let item = app.buttons["验收 Kindle·" + kind]
        let menu = app.scrollViews.containing(.button, identifier: "Kindle 电子书").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        for _ in 0..<4 where !item.isHittable { menu.swipeUp() }
        XCTAssertTrue(item.isHittable)
        item.tap()
        let alert = app.alerts["导入 Kindle 电子书"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let title = "Kindle 验收·\(kind)·\(UUID().uuidString.prefix(6))"
        let field = alert.textFields.firstMatch
        field.tap()
        if let value = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText(title); alert.buttons["导入"].tap()
        return title
    }

    private func openKindle(_ title: String, app: XCUIApplication) {
        let cell = app.collectionViews.cells[title]
        XCTAssertTrue(cell.waitForExistence(timeout: 15)); cell.tap()
        XCTAssertTrue(app.buttons["章节目录"].waitForExistence(timeout: 10)); app.buttons["章节目录"].tap()
        XCTAssertTrue(app.tables.cells.firstMatch.waitForExistence(timeout: 10)); app.tables.cells.firstMatch.tap()
    }

    func testKindleNovelRealImportTextReaderAndSecondChapterResume() {
        let app = launchKindle(), title = importKindle("小说", app: app)
        openKindle(title, app: app); ready(app)
        XCTAssertTrue(app.webViews.staticTexts["第一章"].exists)
        app.buttons["下一节"].tap(); ready(app)
        XCTAssertTrue(app.webViews.staticTexts["Kindle 第二章正文"].exists)
        app.sliders["epub.progress"].adjust(toNormalizedSliderPosition: 0.6)
        let savedPosition = NSPredicate { _, _ in
            guard let value = app.sliders["epub.progress"].value as? String,
                  let number = Double(value.replacingOccurrences(of: "%", with: "")) else { return false }
            return (55...65).contains(number)
        }
        expectation(for: savedPosition, evaluatedWith: app); waitForExpectations(timeout: 5)
        back(app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '继续阅读'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap(); ready(app)
        XCTAssertEqual(app.staticTexts["epub.section"].value as? String, "第2章，第1节")
        expectation(for: savedPosition, evaluatedWith: app); waitForExpectations(timeout: 5)
        app.buttons["排版"].tap()
        XCTAssertTrue(app.buttons["epub.fontSize-Increment"].waitForExistence(timeout: 5))
    }

    func testKindleComicRealImportUsesExistingImageReaderAndResume() {
        let app = launchKindle(), title = importKindle("漫画", app: app)
        openKindle(title, app: app)
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        expectation(for: NSPredicate { _, _ in
            app.collectionViews.cells.count > 0
                && !app.buttons["正在加载图片…"].exists
                && !app.buttons["图片加载失败 · 点击重试"].exists
        }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        back(app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '继续阅读'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 10))
    }

    func testKindleMixedRealImportRetainsTextAndImageInExistingTextReader() {
        let app = launchKindle(), title = importKindle("图文", app: app)
        openKindle(title, app: app); ready(app)
        XCTAssertTrue(app.webViews.staticTexts["第一章"].exists)
        XCTAssertTrue(app.webViews.images.firstMatch.exists)
    }

    func testKindleUnsupportedImportShowsRealParserReasonAndPickerEntryWorks() {
        let app = launchKindle()
        for kind in ["KF8", "DRM"] {
            let title = importKindle(kind, app: app)
            let error = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", kind)).firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 15))
            XCTAssertFalse(app.collectionViews.cells[title].exists)
        }
        app.buttons["本地书架"].tap(); app.buttons["bookshelf.import"].tap(); app.buttons["Kindle 电子书"].tap()
        XCTAssertTrue(app.navigationBars.buttons["取消"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["取消"].tap()
    }
}
