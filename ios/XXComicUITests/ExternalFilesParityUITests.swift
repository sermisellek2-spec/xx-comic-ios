import XCTest

/// Uses an installed, separate app's shared Documents directory. There is no
/// selected-URL injection, app-owned source folder, or fabricated bookmark.
final class ExternalFilesParityUITests: ParityUITestCase {
    private let session = UUID().uuidString
    private var folderName: String { "Files漫画_" + String(session.prefix(8)) }

    private func prepareHost() -> XCUIApplication {
        let host = XCUIApplication(bundleIdentifier: "com.xxcomic.tests.filesfixture")
        host.launchEnvironment["FILES_FIXTURE_SESSION"] = session
        host.launch()
        let ready = host.staticTexts["files.fixture.status"]
        XCTAssertTrue(ready.waitForExistence(timeout: 10))
        XCTAssertEqual(ready.label, "准备完成：" + folderName)
        return host
    }
    private func launch(emptyLibrary: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-reader-original", "--matrix-download-network", "--light-mode"]
        if emptyLibrary { app.launchArguments.append("--matrix-empty-library") }
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = session
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap(); app.cells["settings.storage"].tap()
        XCTAssertTrue(app.buttons["local.folder.link"].waitForExistence(timeout: 10))
        return app
    }
    private func choose(_ name: String, app: XCUIApplication) throws {
        let hostFolder = app.staticTexts["XXComic Files Fixture"]
        let browse = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse"])).firstMatch
        let localNames = ["我的 iPhone", "我的 iPad", "On My iPhone", "On My iPad", "在我的 iPhone 上", "在我的 iPad 上"]
        let local = app.cells.containing(NSPredicate(format: "label IN %@", localNames)).firstMatch
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse", "位置", "Locations", "返回", "Back"] + localNames)).firstMatch
        let sidebar = app.buttons.matching(NSPredicate(format: "label IN %@", ["显示边栏", "Show Sidebar"])).firstMatch
        // Files starts in Recents on a fresh simulator. Its Browse item is a
        // tab button, and its local provider is a cell, not a navigation button.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<8 where !hostFolder.exists {
            if browse.exists && !browse.isSelected { browse.tap() }
            else if local.exists && local.isHittable { local.tap() }
            else if back.exists && back.isHittable { back.tap() }
            else if sidebar.exists && sidebar.isHittable { sidebar.tap() }
            else { break }
        }
        let host = try XCTUnwrap(hostFolder.waitForExistence(timeout: 10) ? hostFolder : nil,
                                 "The separate app must appear in the real Files provider")
        host.tap()
        let target = app.staticTexts[name]
        try XCTUnwrap(target.waitForExistence(timeout: 10) ? target : nil).tap()
        let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["打开", "Open", "完成", "Done"])).firstMatch
        try XCTUnwrap(open.waitForExistence(timeout: 10) && open.isEnabled ? open : nil).tap()
    }
    private func read(_ app: XCUIApplication) {
        app.tabBars.buttons["书架"].tap(); app.buttons["bookshelf.tab.1"].tap()
        let book = app.collectionViews.cells[folderName]
        XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 10)); app.buttons["detail.read"].tap()
        let pixels = app.images.matching(identifier: "reader.image").matching(NSPredicate(format: "value CONTAINS %@", "32x48")).firstMatch
        XCTAssertTrue(pixels.waitForExistence(timeout: 15), "Read actual PNG bytes across the separate app's sandbox")
    }
    func testRealFilesFolderSelectionAndBookmarkReadAfterRelaunch() throws {
        _ = prepareHost(); let app = launch()
        app.buttons["local.folder.link"].tap(); try choose(folderName, app: app)
        XCTAssertTrue(app.staticTexts["已关联文件夹；正文直接读取，原文件保留"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.firstMatch.tap(); read(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10)); read(app)
    }
    func testMissingExternalFolderCanBeReauthorizedThroughRealFiles() throws {
        let host = prepareHost(), app = launch()
        app.buttons["local.folder.link"].tap(); try choose(folderName, app: app)
        XCTAssertTrue(app.staticTexts["已关联文件夹；正文直接读取，原文件保留"].waitForExistence(timeout: 15))
        host.activate(); host.buttons["files.fixture.retire"].tap()
        XCTAssertEqual(host.staticTexts["files.fixture.status"].label, "原目录已失效；新目录：" + folderName + "_新")
        app.activate()
        let folder = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "local.folder.")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10)); folder.tap()
        XCTAssertTrue(app.alerts["重新授权《\(folderName)》"].waitForExistence(timeout: 10))
        app.alerts.buttons["选择文件夹"].tap(); try choose(folderName + "_新", app: app)
        XCTAssertTrue(app.staticTexts["已恢复授权；书名和阅读记录保留"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.firstMatch.tap(); read(app)
    }
    func testRealFilesDownloadLocationIsRetainedAndCompletedPixelsReadAfterRelaunch() throws {
        _ = prepareHost(); let app = launch(emptyLibrary: false)
        app.cells["storage.download-location"].tap()
        app.cells["download.location.choose"].tap(); app.alerts.buttons["选择文件夹"].tap()
        try choose(folderName, app: app)
        let current = app.cells["download.location.current"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", folderName), evaluatedWith: current)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.staticTexts["下载目录已保存；原副本保留"].exists)
        app.navigationBars.buttons.firstMatch.tap(); app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["书架"].tap(); app.buttons["bookshelf.tab.0"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 10)); comic.tap()
        app.buttons["detail.download"].tap()
        XCTAssertTrue(app.tables["download.chapters"].waitForExistence(timeout: 10)); app.buttons["download.start"].tap()
        XCTAssertTrue(app.buttons["detail.download"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap(); app.tabBars.buttons["设置"].tap()
        app.cells["settings.downloads"].tap()
        let read = app.tables["download.tasks"].buttons["阅读"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 20)); XCTAssertTrue(read.isEnabled)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        app.cells["settings.storage"].tap(); app.cells["storage.download-location"].tap()
        XCTAssertTrue(app.cells["download.location.current"].label.contains(folderName), "Persist the actual external Files location")
        app.navigationBars.buttons.firstMatch.tap(); app.navigationBars.buttons.firstMatch.tap()
        app.cells["settings.downloads"].tap()
        let offline = app.tables["download.tasks"].buttons["阅读"].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10)); offline.tap()
        let pixels = app.images.matching(identifier: "reader.image").matching(NSPredicate(format: "value CONTAINS %@", "384x384")).firstMatch
        XCTAssertTrue(pixels.waitForExistence(timeout: 20), "Decode the recorded completed task through the production external-directory image consumer")
    }
}
