import XCTest

final class SourceConfigFilesUITests: ParityUITestCase {
    private let session = UUID().uuidString
    private var folderName: String { "站源配置_" + String(session.prefix(8)) }

    private func prepareHost() -> XCUIApplication {
        let host = XCUIApplication(bundleIdentifier: "com.xxcomic.tests.filesfixture")
        host.launchEnvironment["FILES_FIXTURE_SESSION"] = session; host.launch()
        XCTAssertTrue(host.staticTexts["files.fixture.status"].waitForExistence(timeout: 10))
        XCTAssertEqual(host.staticTexts["files.fixture.status"].label, "准备完成：Files漫画_" + String(session.prefix(8)))
        return host
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures", "--matrix-empty-library", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = session; app.launch()
        openSettings(app); return app
    }
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        app.cells["settings.sources"].tap()
        XCTAssertTrue(app.buttons["source.config.more"].waitForExistence(timeout: 10))
    }
    private func menu(_ title: String, app: XCUIApplication) {
        app.buttons["source.config.more"].tap(); app.buttons[title].tap()
    }
    private func choose(_ filename: String, app: XCUIApplication) throws {
        let files = FilesPickerDriver(app: app)
        try files.openFixtureProvider(); try files.openFolder(folderName); try files.selectFile(filename)
    }
    private func importChanged(_ app: XCUIApplication) throws {
        menu("导入站源配置", app: app); try choose("changed.json", app: app)
        XCTAssertTrue(app.alerts["导入完成"].waitForExistence(timeout: 15))
        app.alerts.buttons["确定"].tap()
        XCTAssertEqual(app.switches["source.enabled.duya"].value as? String, "1")
        XCTAssertEqual(app.switches["source.enabled.mh160"].value as? String, "0")
    }
    func testRealFilesImportPersistsSwitchesAndOrderAcrossRelaunch() throws {
        _ = prepareHost(); let app = launch(); try importChanged(app)
        app.terminate(); app.launch(); openSettings(app)
        XCTAssertEqual(app.switches["source.enabled.duya"].value as? String, "1")
        XCTAssertEqual(app.switches["source.enabled.mh160"].value as? String, "0")
    }
    func testExportWrites51SourceJSONInExternalProviderAndCanReimportIt() throws {
        let host = prepareHost(), app = launch(); try importChanged(app)
        menu("导出站源配置", app: app)
        let files = FilesPickerDriver(app: app)
        try files.openFixtureProvider(); try files.openFolder(folderName); try files.confirmExport()
        XCTAssertTrue(app.alerts["导出完成"].waitForExistence(timeout: 15)); app.alerts.buttons["确定"].tap()
        host.activate(); XCTAssertTrue(host.wait(for: .runningForeground, timeout: 5))
        let verifyButton = host.buttons["files.fixture.verify-export"]
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: verifyButton)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 5), .completed)
        let exportStatus = host.staticTexts["files.fixture.export.status"]
        let expectedExport = "已校验实际文件：51 个站源，50 个开启；毒牙开启，漫画160关闭"
        for _ in 0..<2 {
            verifyButton.tap()
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expectedExport), object: exportStatus)
            if XCTWaiter.wait(for: [finished], timeout: 5) == .completed { break }
        }
        XCTAssertEqual(exportStatus.label, expectedExport)
        app.activate(); XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5)); app.switches["source.enabled.duya"].tap(); app.switches["source.enabled.mh160"].tap()
        XCTAssertEqual(app.switches["source.enabled.duya"].value as? String, "0")
        XCTAssertEqual(app.switches["source.enabled.mh160"].value as? String, "1")
        menu("导入站源配置", app: app); try choose("xx-comic-sources.json", app: app)
        XCTAssertTrue(app.alerts["导入完成"].waitForExistence(timeout: 15)); app.alerts.buttons["确定"].tap()
        XCTAssertEqual(app.switches["source.enabled.duya"].value as? String, "1")
        XCTAssertEqual(app.switches["source.enabled.mh160"].value as? String, "0")
    }
    func testMalformedFileDoesNotPartiallyImportAndCanRetryWithoutLeavingManagement() throws {
        _ = prepareHost(); let app = launch()
        menu("导入站源配置", app: app); try choose("invalid.json", app: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.alerts.staticTexts["站源配置字段格式错误，未修改现有配置"].exists)
        app.alerts.buttons["确定"].tap()
        XCTAssertEqual(app.switches["source.enabled.mh160"].value as? String, "1")
        XCTAssertEqual(app.switches["source.enabled.gmh"].value as? String, "1")
        try importChanged(app)
    }
    func testUnsupportedConfigurationIsReportedAndRetiredSourcesStayExcluded() throws {
        _ = prepareHost(); let app = launch()
        menu("导入站源配置", app: app); try choose("partial.json", app: app)
        let result = app.alerts["部分配置已导入"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        XCTAssertTrue(result.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@", "gmh.routes.fictional", "baozimh", "custom-test")).firstMatch.exists)
        result.buttons["确定"].tap()
        XCTAssertEqual(app.switches["source.enabled.gmh"].value as? String, "0")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.cells["settings.sources"].staticTexts["49 个开启"].exists)
    }
    func testCancellingImportAndExportLeavesConfigurationAndShowsNoFalseSuccess() throws {
        let app = launch()
        for title in ["导入站源配置", "导出站源配置"] {
            menu(title, app: app)
            try FilesPickerDriver(app: app).cancelPicker()
            XCTAssertTrue(app.buttons["source.config.more"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.alerts.firstMatch.exists)
            XCTAssertEqual(app.switches["source.enabled.mh160"].value as? String, "1")
        }
    }
}
