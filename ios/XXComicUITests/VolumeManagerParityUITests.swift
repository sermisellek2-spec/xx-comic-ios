import XCTest
import UIKit

final class VolumeManagerParityUITests: ParityUITestCase {
    private let session = UUID().uuidString
    private var folder: String { "Files漫画_" + String(session.prefix(8)) }
    private let bookTitle = "EPUB 验收·图片"
    private func launch(dark: Bool = false, flags: [String] = []) -> (XCUIApplication, XCUIApplication) {
        let host = XCUIApplication(bundleIdentifier: "com.xxcomic.tests.filesfixture")
        host.launchEnvironment["FILES_FIXTURE_SESSION"] = session; host.launch()
        XCTAssertTrue(host.staticTexts["files.fixture.status"].waitForExistence(timeout: 10))
        XCTAssertEqual(host.staticTexts["files.fixture.status"].label, "准备完成：" + folder)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--epub-fixtures", "--matrix-reader-original", dark ? "--dark-mode" : "--light-mode"] + flags
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = session; app.launch(); openBook(app)
        return (app, host)
    }
    private func openBook(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10)); app.tabBars.buttons["书架"].tap()
        app.buttons["bookshelf.tab.1"].tap()
        let book = app.collectionViews.cells[bookTitle]
        XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap()
        XCTAssertTrue(app.buttons["detail.volumes"].waitForExistence(timeout: 10))
    }
    private func openManager(_ app: XCUIApplication, count: Int) {
        app.buttons["detail.volumes"].tap(); assertCount(count, app: app)
    }
    private func assertCount(_ count: Int, app: XCUIApplication) {
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "共 \(count) 卷"), object: app.staticTexts["volumes.count"])
        XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: 15), .completed)
        XCTAssertEqual(app.tables["volumes.list"].cells.count, count)
        XCTAssertTrue(app.buttons["volumes.append"].isEnabled)
    }
    private func append(_ file: String, count: Int, app: XCUIApplication) throws {
        app.buttons["volumes.append"].tap()
        let driver = FilesPickerDriver(app: app); try driver.openFixtureProvider(); try driver.openFolder(folder); try driver.selectFile(file)
        // Multi-selection pickers can retain the selection until Open is pressed.
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        if picker.exists { try driver.confirmFolder() }
        assertCount(count, app: app)
    }
    private func row(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.tables["volumes.list"].cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }
    private func verifyOriginals(_ host: XCUIApplication) {
        host.activate(); host.buttons["files.fixture.verify-originals"].tap()
        XCTAssertEqual(host.staticTexts["files.fixture.originals.status"].label, "原目录两张图片完整：32×48")
    }
    func testRealFilesAppendAndDragOrderRetainTheOriginalChapterAcrossRelaunch() throws {
        let (app, host) = launch()
        app.buttons["detail.directory"].tap()
        let second = app.tables["chapter.list"].cells.containing(.staticText, identifier: "第二章").firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 10)); XCTAssertTrue(second.isHittable); second.tap()
        XCTAssertTrue(app.images["reader.image"].firstMatch.waitForExistence(timeout: 10)); app.buttons["reader.back"].tap()
        openManager(app, count: 1); try append("01.png", count: 2, app: app); try append("02.png", count: 3, app: app)
        let original = row(bookTitle, app: app), last = row("02", app: app)
        XCTAssertTrue(original.exists); XCTAssertTrue(last.exists)
        let start = original.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: original.frame.width - 18, dy: original.frame.height / 2))
        let target = last.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: last.frame.width - 18, dy: last.frame.height * 0.9))
        start.press(forDuration: 0.5, thenDragTo: target)
        XCTAssertTrue(app.staticTexts["分卷顺序已保存"].waitForExistence(timeout: 10))
        XCTAssertTrue((original.value as? String)?.hasPrefix("第 3 卷") == true)
        app.buttons["volumes.close"].tap(); app.terminate(); app.launch(); openBook(app)
        openManager(app, count: 3)
        XCTAssertTrue((row(bookTitle, app: app).value as? String)?.hasPrefix("第 3 卷") == true)
        app.buttons["volumes.close"].tap(); app.buttons["detail.read"].tap()
        let pixels = app.images.matching(identifier: "reader.image").matching(NSPredicate(format: "value CONTAINS ':32x32'")).firstMatch
        XCTAssertTrue(pixels.waitForExistence(timeout: 15)); XCTAssertTrue(app.staticTexts["reader.title"].label.contains("第二章"))
        verifyOriginals(host)
    }
    func testVolumeUndoThenConfirmedRemovalSurviveRelaunchAndPreserveExternalFiles() throws {
        let (app, host) = launch(); openManager(app, count: 1); try append("01.png", count: 2, app: app)
        app.buttons["移除 01"].tap(); XCTAssertTrue(app.buttons["volumes.undo"].waitForExistence(timeout: 2)); app.buttons["volumes.undo"].tap()
        assertCount(2, app: app); XCTAssertTrue(row("01", app: app).exists)
        app.buttons["移除 01"].tap()
        XCTAssertTrue(app.staticTexts["分卷已移除，原文件保留"].waitForExistence(timeout: 10)); assertCount(1, app: app)
        app.buttons["volumes.close"].tap(); app.terminate(); app.launch(); openBook(app); openManager(app, count: 1)
        XCTAssertFalse(row("01", app: app).exists); app.buttons["volumes.close"].tap(); verifyOriginals(host)
    }
    func testCancellingRealFilesAppendKeepsTheExistingVolume() throws {
        let (app, _) = launch(); openManager(app, count: 1); app.buttons["volumes.append"].tap()
        try FilesPickerDriver(app: app).cancelPicker(); assertCount(1, app: app)
        XCTAssertFalse(app.alerts.firstMatch.exists); app.buttons["volumes.close"].tap()
        app.buttons["detail.read"].tap()
        let pixels = app.images.matching(identifier: "reader.image").matching(NSPredicate(format: "value CONTAINS ':32x32'")).firstMatch
        XCTAssertTrue(pixels.waitForExistence(timeout: 15))
    }
    func testVolumeSheetThemesAndRotationKeepAllControlsAndRowsReachable() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        for dark in [false, true] {
            XCUIDevice.shared.orientation = .portrait
            let (app, _) = launch(dark: dark); openManager(app, count: 1)
            for landscape in [false, true] {
                XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let window = app.windows.firstMatch.frame
                    return (window.width > window.height) == landscape
                }, object: app)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
                let frame = app.windows.firstMatch.frame
                XCTAssertEqual(frame.width > frame.height, landscape)
                XCTAssertTrue(app.buttons["volumes.append"].isHittable); XCTAssertTrue(app.buttons["volumes.close"].isHittable)
                XCTAssertTrue(row(bookTitle, app: app).isHittable); XCTAssertTrue(app.buttons["移除 " + bookTitle].isHittable)
                let prefix = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
                let name = "\(prefix)_\(landscape ? "landscape" : "portrait")_\(dark ? "dark" : "light")_volume_manager"
                let screenshot = XCUIScreen.main.screenshot()
                let shot = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: "public.png")
                shot.name = name; shot.lifetime = .keepAlways; add(shot)
                let metadata: [String: Any] = ["scene": name, "fixtureID": "real-comic-epub-volume-v1",
                    "appFrame": ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)],
                    "screenScale": Double(UIScreen.main.scale), "rasterPixelSize": [screenshot.image.cgImage?.width ?? 0, screenshot.image.cgImage?.height ?? 0],
                    "preferredContentSizeCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
                    "capturedAtUTC": ISO8601DateFormatter().string(from: Date()), "accessibilitySnapshot": app.debugDescription,
                    "steps": "Import a genuine image-only EPUB, open its production volume manager, then rotate the same visible sheet"]
                let proof = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metadata, options: .sortedKeys), uniformTypeIdentifier: "public.json")
                proof.name = "provenance-" + name; proof.lifetime = .keepAlways; add(proof)
            }
            app.terminate()
        }
    }
    func testCancellingPendingAppendKeepsTheOwnedVolumeAndOriginalFileAfterRelaunch() throws {
        let (app, host) = launch(flags: ["--volume-append-held-until-cancel"]); openManager(app, count: 1)
        app.buttons["volumes.append"].tap()
        let driver = FilesPickerDriver(app: app); try driver.openFixtureProvider(); try driver.openFolder(folder); try driver.selectFile("01.png")
        if app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].exists { try driver.confirmFolder() }
        XCTAssertTrue(app.buttons["volumes.append.cancel"].waitForExistence(timeout: 10)); app.buttons["volumes.append.cancel"].tap()
        assertCount(1, app: app); XCTAssertFalse(row("01", app: app).exists)
        app.buttons["volumes.close"].tap(); app.terminate(); app.launch(); openBook(app); openManager(app, count: 1)
        XCTAssertFalse(row("01", app: app).exists); verifyOriginals(host)
    }
}
