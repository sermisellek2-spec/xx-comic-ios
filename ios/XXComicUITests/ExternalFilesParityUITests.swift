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
        let files = FilesPickerDriver(app: app, capture: captureFilesState)
        try files.openFixtureProvider()
        try files.openFolder(name)
        try files.confirmFolder()
    }
    private func captureFilesState(_ name: String) {
        let image = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        image.name = "files-" + name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: XCUIApplication().debugDescription)
        tree.name = "files-" + name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
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
    func testForegroundFolderSyncAddsRenamesRemovesAndRestoresActualExternalPages() throws {
        let host = prepareHost(), app = launch()
        app.buttons["local.folder.link"].tap(); try choose(folderName, app: app)
        XCTAssertTrue(app.staticTexts["已关联文件夹；正文直接读取，原文件保留"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.firstMatch.tap(); read(app)
        app.sliders["reader.seek"].adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue((app.collectionViews["reader.pages"].value as? String)?.contains("第 2 页，共 2 页") == true)
        func returnToStorage() {
            app.buttons["reader.back"].tap(); app.navigationBars.buttons.firstMatch.tap()
            app.tabBars.buttons["设置"].tap(); app.cells["settings.storage"].tap()
        }
        func waitForCount(_ count: Int) {
            let record = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "local.folder.")).firstMatch
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "\(count) 张图片 · 正常同步"), object: record)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        }
        returnToStorage(); host.activate(); host.buttons["files.fixture.change-images"].tap()
        XCTAssertEqual(host.staticTexts["files.fixture.status"].label, "已新增03并将02改名04：3张图片")
        app.activate(); waitForCount(3)
        app.navigationBars.buttons.firstMatch.tap(); read(app)
        XCTAssertTrue((app.collectionViews["reader.pages"].value as? String)?.contains("第 3 页，共 3 页") == true, "Rename must retain the same page identity while the new picture shifts its index")
        app.sliders["reader.seek"].adjust(toNormalizedSliderPosition: 0.5)
        let changedPixels = app.images.matching(identifier: "reader.image").matching(NSPredicate(format: "value CONTAINS ':64x96'")).firstMatch
        XCTAssertTrue(changedPixels.waitForExistence(timeout: 15), "Decode the new external file, rather than a copied or stale image")
        returnToStorage(); host.activate(); host.buttons["files.fixture.remove-first-image"].tap()
        XCTAssertEqual(host.staticTexts["files.fixture.status"].label, "已移除01：2张图片，03和04保留")
        app.activate(); waitForCount(2); app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10)); app.tabBars.buttons["书架"].tap(); app.buttons["bookshelf.tab.1"].tap()
        let book = app.collectionViews.cells[folderName]; XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap(); app.buttons["detail.read"].tap()
        XCTAssertTrue(changedPixels.waitForExistence(timeout: 15))
        XCTAssertTrue((app.collectionViews["reader.pages"].value as? String)?.contains("第 1 页，共 2 页") == true)
        XCTAssertFalse(app.alerts.firstMatch.exists)
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
        let host = prepareHost(), app = launch(emptyLibrary: false)
        app.cells["storage.download-location"].tap()
        app.cells["download.location.choose"].tap(); app.alerts.buttons["选择文件夹"].tap()
        try choose(folderName, app: app)
        let current = app.cells["download.location.current"]
        expectation(for: NSPredicate(format: "value CONTAINS %@", folderName), evaluatedWith: current)
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
        host.activate(); host.buttons["files.fixture.verify-download"].tap()
        let external = host.staticTexts["files.fixture.download.status"]
        expectation(for: NSPredicate(format: "label == %@", "已校验外部目录下载像素：384×384，原文件保留"), evaluatedWith: external)
        waitForExpectations(timeout: 15)
        app.activate()
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        app.cells["settings.storage"].tap(); app.cells["storage.download-location"].tap()
        XCTAssertTrue((app.cells["download.location.current"].value as? String)?.contains(folderName) == true, "Persist the actual external Files location")
        app.navigationBars.buttons.firstMatch.tap(); app.navigationBars.buttons.firstMatch.tap()
        app.cells["settings.downloads"].tap()
        let offline = app.tables["download.tasks"].buttons["阅读"].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10)); offline.tap()
        let pixels = app.images.matching(identifier: "reader.image").matching(NSPredicate(format: "value CONTAINS %@", "384x384")).firstMatch
        XCTAssertTrue(pixels.waitForExistence(timeout: 20), "Decode the recorded completed task through the production external-directory image consumer")
    }
}
