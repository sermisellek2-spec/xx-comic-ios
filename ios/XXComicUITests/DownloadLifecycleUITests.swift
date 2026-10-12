import XCTest

final class DownloadLifecycleUITests: ParityUITestCase {
    private func preparePendingDownload() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-download-network", "--matrix-reader-original", "--matrix-held-download-once", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        let comic = app.collectionViews.cells["电锯人"].firstMatch
        XCTAssertTrue(comic.waitForExistence(timeout: 10)); comic.tap()
        app.buttons["detail.download"].tap()
        XCTAssertTrue(app.tables["download.chapters"].waitForExistence(timeout: 5))
        app.buttons["download.start"].tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.tables["download.chapters"])
        wait(for: [closed], timeout: 10)
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        openDownloadCenter(app)
        let progress = app.staticTexts["download.task.status"].firstMatch
        let pending = NSPredicate(format: "value BEGINSWITH %@ AND value CONTAINS %@", "DOWNLOADING;", ";done=1;total=4")
        expectation(for: pending, evaluatedWith: progress)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["download.backgroundHint"].exists)
        return app
    }

    private func openDownloadCenter(_ app: XCUIApplication) {
        app.tabBars.buttons["设置"].tap()
        let center = app.tables.cells.containing(.staticText, identifier: "下载中心").firstMatch
        XCTAssertTrue(center.waitForExistence(timeout: 5)); center.tap()
        XCTAssertTrue(app.tables["download.tasks"].waitForExistence(timeout: 5))
    }

    private func checkCompletedOfflineRead(_ app: XCUIApplication, timeout: TimeInterval) {
        let read = app.tables["download.tasks"].buttons["阅读"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: timeout), "Recovery must finish without tapping resume/retry")
        read.tap()
        let image = app.images["reader.image"].firstMatch
        let decoded = NSPredicate(format: "value CONTAINS %@", ":384x384")
        expectation(for: decoded, evaluatedWith: image)
        waitForExpectations(timeout: 10)
    }

    func testTerminatedDownloadResumesFromPublishedPageAfterRelaunch() {
        let app = preparePendingDownload()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10))
        openDownloadCenter(app)
        checkCompletedOfflineRead(app, timeout: 20)
    }

    func testActualBackgroundAndForegroundContinueWithoutManualRetry() {
        let app = preparePendingDownload()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 6), "Wait for the real Home transition before checking background state")
        XCTAssertEqual(app.state, .runningBackground)
        app.activate()
        XCTAssertTrue(app.tables["download.tasks"].waitForExistence(timeout: 10))
        // The first real HTTP response is intentionally held. Its timeout and
        // automatic retry must be handled by the runtime, with no button tap.
        checkCompletedOfflineRead(app, timeout: 40)
    }
}
