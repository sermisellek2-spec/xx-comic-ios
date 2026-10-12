import XCTest

final class BookshelfParityUITests: ParityUITestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"] + (large ? ["--matrix-large-bookshelf"] : [])
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10)); app.buttons["我的书架"].tap()
        return app
    }

    func testActualUnreadCountLatestChapterAndReadingPositionAppearInGridAndList() {
        let app = launch()
        let read = app.collectionViews.cells["电锯人"], unread = app.collectionViews.cells["间谍过家家"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertEqual(read.value as? String, "未读 5 · 更新至 第6话")
        XCTAssertEqual(unread.value as? String, "未读 6 · 更新至 第6话")
        app.buttons["bookshelf.layout"].tap()
        XCTAssertEqual(read.value as? String, "未读 5 · 更新至 第6话")
        XCTAssertEqual(unread.value as? String, "未读 6 · 更新至 第6话")
    }

    func testSwitchingGridToListKeepsVisibleComic() {
        let app = launch(large: true)
        let list = app.collectionViews.firstMatch
        list.swipeUp(); list.swipeUp()
        let visible = list.cells.allElementsBoundByIndex.first { $0.isHittable && $0.label.hasPrefix("验收漫画") }
        XCTAssertNotNil(visible)
        guard let title = visible?.label else { return }
        app.buttons["bookshelf.layout"].tap()
        XCTAssertTrue(list.cells[title].isHittable, "Layout switching must keep a visible book instead of returning to the top")
    }

    func testResumeRowOpensSavedChapterWithOneTapAndRetainsReturnPath() {
        let app = launch()
        let resume = app.buttons["bookshelf.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertEqual(resume.value as? String, "电锯人，上次看到 · 第 1 话")
        resume.tap()
        XCTAssertTrue(app.navigationBars["第1话"].waitForExistence(timeout: 10), "A single resume action must enter the saved chapter")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["bookshelf.resume"].waitForExistence(timeout: 5))
    }

    private func openMove(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10)); app.buttons["我的书架"].tap()
        let book = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.press(forDuration: 1)
        XCTAssertTrue(app.buttons["移动"].waitForExistence(timeout: 5)); app.buttons["移动"].tap()
        XCTAssertTrue(app.navigationBars["移动至分组"].waitForExistence(timeout: 5))
    }
    private func moveGroup(_ name: String, app: XCUIApplication) -> XCUIElement {
        app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "bookshelf.group.select.", name)).firstMatch
    }
    private func createMoveGroup(_ name: String, app: XCUIApplication) {
        app.buttons["+ 新建分组"].tap()
        let alert = app.alerts["新建分组"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText(name)
        alert.buttons["创建"].tap()
        XCTAssertTrue(moveGroup(name, app: app).waitForExistence(timeout: 5))
    }

    func testNewGroupsPreserveMoveDraftAndMembershipAcrossRelaunch() {
        let app = launch(); openMove(app)
        createMoveGroup("验收组甲", app: app)
        XCTAssertEqual(moveGroup("验收组甲", app: app).value as? String, "已选择")
        createMoveGroup("验收组乙", app: app)
        XCTAssertEqual(moveGroup("验收组甲", app: app).value as? String, "已选择")
        XCTAssertEqual(moveGroup("验收组乙", app: app).value as? String, "已选择")
        app.navigationBars["移动至分组"].buttons["完成"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5), "Assigning a custom group must retain the book in 全部")
        app.terminate(); app.launch(); openMove(app)
        XCTAssertEqual(moveGroup("验收组甲", app: app).value as? String, "已选择")
        XCTAssertEqual(moveGroup("验收组乙", app: app).value as? String, "已选择")
    }

    func testCancellingMoveAfterCreatingAGroupPreservesExistingMembership() {
        let app = launch(); openMove(app)
        createMoveGroup("已有组", app: app)
        app.navigationBars["移动至分组"].buttons["取消"].tap()
        openMove(app)
        XCTAssertEqual(moveGroup("已有组", app: app).value as? String, "未选择")
        moveGroup("已有组", app: app).tap()
        createMoveGroup("新建组", app: app)
        XCTAssertEqual(moveGroup("已有组", app: app).value as? String, "已选择")
        XCTAssertEqual(moveGroup("新建组", app: app).value as? String, "已选择")
        app.navigationBars["移动至分组"].buttons["取消"].tap()
        app.terminate(); app.launch(); openMove(app)
        XCTAssertEqual(moveGroup("已有组", app: app).value as? String, "未选择")
        XCTAssertEqual(moveGroup("新建组", app: app).value as? String, "未选择")
    }

    func testEmptyGroupNameShowsAnErrorAndAllowsCreatingAfterRetry() {
        let app = launch(); openMove(app)
        app.buttons["+ 新建分组"].tap()
        XCTAssertTrue(app.alerts["新建分组"].waitForExistence(timeout: 5))
        app.alerts["新建分组"].buttons["创建"].tap()
        let error = app.alerts["分组操作失败"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.staticTexts["分组名称不能为空"].exists)
        error.buttons["确定"].tap()
        XCTAssertTrue(app.navigationBars["移动至分组"].exists)
        createMoveGroup("空名重试组", app: app)
        XCTAssertEqual(moveGroup("空名重试组", app: app).value as? String, "已选择")
    }

    func testRenamingDeletingAndUndoingAGroupRetainsItsBookAndMembership() {
        let app = launch(); openMove(app)
        createMoveGroup("管理验收组", app: app)
        app.navigationBars["移动至分组"].buttons["完成"].tap()
        app.buttons["bookshelf.groups"].tap()
        XCTAssertTrue(app.navigationBars["分组管理"].waitForExistence(timeout: 5))
        app.buttons["重命名分组“管理验收组”"].tap()
        let rename = app.alerts["重命名分组"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.textFields.firstMatch.tap()
        rename.textFields.firstMatch.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "管理验收组".count) + "改名验收组")
        rename.buttons["确定"].tap()
        let delete = app.buttons["删除分组“改名验收组”"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertTrue(app.buttons["删除分组"].waitForExistence(timeout: 5)); app.buttons["删除分组"].tap()
        let undo = app.alerts["已删除分组“改名验收组”"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.buttons["撤销"].tap()
        XCTAssertTrue(app.buttons["删除分组“改名验收组”"].waitForExistence(timeout: 5))
        app.cells["bookshelf.group.manage.builtin_online_all"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); openMove(app)
        XCTAssertEqual(moveGroup("改名验收组", app: app).value as? String, "已选择")
        XCTAssertFalse(moveGroup("管理验收组", app: app).exists)
    }
}
