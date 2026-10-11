import XCTest

final class BatchImportRecoveryUITests: ParityUITestCase {
    private func launch(session: String, flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-empty-library", "--epub-fixtures", "--batch-import-fixtures", "--light-mode"] + flags
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = session
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func resume(_ app: XCUIApplication) {
        XCTAssertTrue(app.alerts["未完成的批量导入"].waitForExistence(timeout: 5))
        app.alerts.buttons["选择文件恢复"].tap()
        XCTAssertTrue(app.alerts["恢复批量导入"].waitForExistence(timeout: 5))
        app.alerts.buttons["恢复已匹配项目"].tap()
    }

    func testRecoveredBookRemainsSingleAndCompletedAfterRelaunch() {
        let session = UUID().uuidString
        var app = launch(session: session)
        resume(app)
        XCTAssertTrue(app.buttons["批量导入完成，共 2 卷"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.collectionViews.cells["恢复验收漫画"].waitForExistence(timeout: 5))
        app.terminate()
        app = launch(session: session)
        XCTAssertFalse(app.alerts["未完成的批量导入"].waitForExistence(timeout: 3))
        app.buttons["本地书架"].tap()
        XCTAssertTrue(app.collectionViews.cells["恢复验收漫画"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.collectionViews.cells.matching(identifier: "恢复验收漫画").count, 1)
    }

    func testCancellingRecoveryKeepsPendingTaskAvailableAfterRestart() {
        let session = UUID().uuidString
        var app = launch(session: session)
        XCTAssertTrue(app.alerts["未完成的批量导入"].waitForExistence(timeout: 5))
        app.alerts.buttons["选择文件恢复"].tap()
        XCTAssertTrue(app.alerts["恢复批量导入"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        app.terminate()
        app = launch(session: session)
        XCTAssertTrue(app.alerts["未完成的批量导入"].waitForExistence(timeout: 5))
        app.alerts.buttons["稍后"].tap()
        app.buttons["本地书架"].tap()
        app.buttons["bookshelf.import"].tap()
        XCTAssertTrue(app.buttons["继续上次批量导入"].waitForExistence(timeout: 3))
    }

    func testPartiallyReselectedFilesReportFailureAndRemainingVolumeCanResume() {
        let session = UUID().uuidString
        var app = launch(session: session, flags: ["--batch-select-one"])
        resume(app)
        XCTAssertTrue(app.alerts["批量导入结果"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 卷成功，1 卷失败")).firstMatch.exists)
        app.alerts.buttons["稍后"].tap()
        app.terminate()
        app = launch(session: session)
        resume(app)
        XCTAssertTrue(app.buttons["批量导入完成，共 2 卷"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.collectionViews.cells.matching(identifier: "恢复验收漫画").count, 1)
    }

    func testExplicitBatchPickerSupportsOneFileThroughBatchConfirmation() {
        let app = launch(session: UUID().uuidString, flags: ["--batch-new-import", "--batch-select-one"])
        app.buttons["本地书架"].tap()
        app.buttons["bookshelf.import"].tap()
        app.buttons["批量导入多文件 (ZIP/EPUB/PDF)"].tap()
        XCTAssertTrue(app.buttons["确认导入 (1 卷)"].waitForExistence(timeout: 5))
        app.buttons["确认导入 (1 卷)"].tap()
        XCTAssertTrue(app.buttons["批量导入完成，共 1 卷"].waitForExistence(timeout: 10))
    }
}
