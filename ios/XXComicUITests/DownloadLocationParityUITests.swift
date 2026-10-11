import XCTest

final class DownloadLocationParityUITests: ParityUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap(); app.cells["settings.storage"].tap()
        XCTAssertTrue(app.cells["storage.download-location"].waitForExistence(timeout: 5)); app.cells["storage.download-location"].tap()
        XCTAssertTrue(app.cells["download.location.current"].waitForExistence(timeout: 5))
        return app
    }
    func testCancelLocationConfirmationKeepsDefaultAndDoesNotQueueDownloads() {
        let app = launch(), current = app.cells["download.location.current"].label
        app.cells["download.location.choose"].tap()
        XCTAssertTrue(app.alerts["更改离线下载目录"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertEqual(app.cells["download.location.current"].label, current)
    }
    func testFilesPickerCanCancelWithoutChangingDefault() {
        let app = launch(), current = app.cells["download.location.current"].label
        app.cells["download.location.choose"].tap(); app.alerts.buttons["选择文件夹"].tap()
        let cancel = app.navigationBars.buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertTrue(app.cells["download.location.current"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.cells["download.location.current"].label, current)
    }
}
