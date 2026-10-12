import XCTest

final class SourceGroupsParityUITests: ParityUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); management(app)
        return app
    }
    private func management(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap(); app.tables.staticTexts["站源管理"].tap()
        app.tables.staticTexts["站源分组"].tap()
        XCTAssertTrue(app.buttons["source-groups.create"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["source-group.row.builtin_source_all"].staticTexts["(51)"].exists)
    }
    private func create(_ name: String, app: XCUIApplication) {
        app.buttons["source-groups.create"].tap()
        let form = app.alerts["新建站源分组"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        if !name.isEmpty { form.textFields.firstMatch.tap(); form.textFields.firstMatch.typeText(name) }
        form.buttons["保存"].tap()
    }
    private func row(_ name: String, app: XCUIApplication) -> XCUIElement {
        app.cells.containing(.staticText, identifier: name).firstMatch
    }
    private func action(_ prefix: String, row: XCUIElement) -> XCUIElement {
        row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }
    private func reveal(_ option: XCUIElement, app: XCUIApplication, upwards: Bool) {
        let table = app.tables["source-group.selection.list"]
        for _ in 0..<18 where !option.isHittable {
            if upwards { table.swipeUp() } else { table.swipeDown() }
        }
        XCTAssertTrue(option.isHittable)
    }
    func testDisabledSourceCanJoinAGroupAndSavedMembershipSurvivesCancelRenameAndRelaunch() {
        let app = launch(); create("站源验收组", app: app)
        XCTAssertTrue(app.buttons["source-group.selection.save"].waitForExistence(timeout: 5))
        app.cells["source-group.selection.mh160"].tap()
        let disabled = app.cells["source-group.selection.duya"]
        reveal(disabled, app: app, upwards: true)
        XCTAssertTrue(disabled.staticTexts["毒牙漫画（未启用）"].exists); disabled.tap()
        XCTAssertTrue(app.staticTexts["已选 2 个"].exists)
        app.buttons["source-group.selection.save"].tap()
        let group = row("站源验收组", app: app)
        XCTAssertTrue(group.waitForExistence(timeout: 5)); XCTAssertTrue(group.staticTexts["(2)"].exists)
        action("source-group.sources.", row: group).tap()
        let removed = app.cells["source-group.selection.duya"]
        reveal(removed, app: app, upwards: true); removed.tap()
        XCTAssertTrue(app.staticTexts["已选 1 个"].exists)
        app.buttons["source-group.selection.cancel"].tap()
        XCTAssertTrue(group.staticTexts["(2)"].waitForExistence(timeout: 5))
        action("source-group.rename.", row: group).tap()
        let rename = app.alerts["重命名分组"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5)); rename.textFields.firstMatch.tap()
        rename.textFields.firstMatch.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "站源验收组".count) + "保留站源组")
        rename.buttons["保存"].tap()
        XCTAssertTrue(row("保留站源组", app: app).waitForExistence(timeout: 5))
        app.terminate(); app.launch(); management(app)
        let saved = row("保留站源组", app: app)
        XCTAssertTrue(saved.staticTexts["(2)"].exists)
        action("source-group.sources.", row: saved).tap()
        XCTAssertTrue(app.staticTexts["已选 2 个"].waitForExistence(timeout: 5))
        reveal(app.cells["source-group.selection.duya"], app: app, upwards: true)
        XCTAssertTrue(app.cells["source-group.selection.duya"].staticTexts["毒牙漫画（未启用）"].exists)
        XCTAssertEqual(app.cells["source-group.selection.duya"].value as? String, "已选择")
    }
    func testInvalidNamesShowActualFailureAndDeletingAGroupKeepsTheSourceSwitches() {
        let app = launch(); create("", app: app)
        let failure = app.alerts["分组操作失败"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5)); XCTAssertTrue(failure.staticTexts["分组名称不能为空"].exists)
        failure.buttons["确定"].tap(); create("空组验收", app: app)
        XCTAssertTrue(app.buttons["source-group.selection.cancel"].waitForExistence(timeout: 5))
        app.buttons["source-group.selection.cancel"].tap()
        XCTAssertTrue(row("空组验收", app: app).waitForExistence(timeout: 5))
        create("空组验收", app: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 5)); XCTAssertTrue(failure.staticTexts["分组名称已存在"].exists)
        failure.buttons["确定"].tap()
        let group = row("空组验收", app: app)
        action("source-group.delete.", row: group).tap(); app.alerts["删除分组"].buttons["取消"].tap()
        XCTAssertTrue(group.exists)
        action("source-group.delete.", row: group).tap(); app.alerts["删除分组"].buttons["删除"].tap()
        XCTAssertFalse(group.waitForExistence(timeout: 1))
        app.buttons["source-groups.close"].tap()
        XCTAssertEqual(app.switches["source.enabled.mh160"].value as? String, "1")
        app.tables.firstMatch.swipeUp()
        let duya = app.switches["source.enabled.duya"]
        for _ in 0..<18 where !duya.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertEqual(duya.value as? String, "0")
        app.terminate(); app.launch(); management(app)
        XCTAssertFalse(row("空组验收", app: app).exists)
    }
}
