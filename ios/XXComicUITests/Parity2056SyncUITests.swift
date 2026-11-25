import XCTest

final class Parity2056SyncUITests: ParityUITestCase {
    private func launch(_ flags: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-catalog-fixtures", "--light-mode"] + flags
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 10))
        return app
    }

    private func openSettingsItem(_ identifier: String, app: XCUIApplication) {
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let cell = app.tables.cells[identifier]
        for _ in 0..<8 where !cell.isSafelyHittable(in: app) {
            if cell.exists, !cell.frame.isEmpty, cell.frame.maxY <= table.frame.minY + 10 {
                table.swipeDown()
            } else {
                table.swipeUp()
            }
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.isSafelyHittable(in: app))
        cell.tap()
    }

    func testSettings2056RowsSharePosterBlacklistAndAboutDisclaimer() {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables.cells.count, 13)

        let shareHeader = app.buttons["settings.share.header"]
        XCTAssertTrue(shareHeader.waitForExistence(timeout: 5))
        shareHeader.tap()
        XCTAssertTrue(app.buttons["share.poster.image"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        openSettingsItem("settings.blacklist", app: app)
        XCTAssertTrue(app.staticTexts["黑名单是空的"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        openSettingsItem("settings.about", app: app)
        XCTAssertTrue(app.tables.staticTexts["2.0.56 (356)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tables.staticTexts["61 个"].exists)
        let aboutTable = app.tables.firstMatch
        let introText = aboutTable.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "多站源搜索、在线阅读与本地漫画管理")).firstMatch
        for _ in 0..<6 where !introText.isSafelyHittable(in: app) {
            aboutTable.swipeUp()
        }
        XCTAssertTrue(introText.waitForExistence(timeout: 5))
        let disclaimerText = aboutTable.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本应用提供漫画检索、浏览与本地文件阅读功能")).firstMatch
        for _ in 0..<6 where !disclaimerText.isSafelyHittable(in: app) {
            aboutTable.swipeUp()
        }
        XCTAssertTrue(disclaimerText.waitForExistence(timeout: 5))
    }

    func testDiscoverDualTabSwitchRecommendPrefAndSourceChooser() {
        let app = launch()
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.collectionViews["discover.collection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 5))

        let recTab = app.buttons["discover.tab.recommend"]
        XCTAssertTrue(recTab.waitForExistence(timeout: 5))
        recTab.tap()
        XCTAssertTrue(app.collectionViews["recommend.collection"].waitForExistence(timeout: 5))
        let prefBtn = app.buttons["recommend.pref"]
        XCTAssertTrue(prefBtn.waitForExistence(timeout: 5))
        prefBtn.tap()
        XCTAssertTrue(app.buttons["recommend.pref.close"].waitForExistence(timeout: 5))
        app.buttons["recommend.pref.close"].tap()
        XCTAssertFalse(app.buttons["recommend.pref.close"].waitForExistence(timeout: 2))

        let discoverTab = app.buttons["discover.tab.discover"]
        XCTAssertTrue(discoverTab.waitForExistence(timeout: 5))
        discoverTab.tap()
        XCTAssertTrue(app.buttons["discover.source"].waitForExistence(timeout: 5))
        app.buttons["discover.source"].tap()
        XCTAssertTrue(app.tables["source.chooser.list"].waitForExistence(timeout: 5))
        app.buttons["source.chooser.close"].tap()
    }

    func testBookshelfBlacklistHideAndSettingsRestoreAcrossTabs() {
        let app = launch()
        app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 10))
        comic.press(forDuration: 1.5)

        let blacklistAction = app.buttons["拉黑"]
        XCTAssertTrue(blacklistAction.waitForExistence(timeout: 5))
        blacklistAction.tap()

        let confirmAlert = app.alerts["加入黑名单"]
        XCTAssertTrue(confirmAlert.waitForExistence(timeout: 5))
        confirmAlert.buttons["加入黑名单"].tap()

        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: comic)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)

        app.tabBars.buttons["设置"].tap()
        openSettingsItem("settings.blacklist", app: app)
        XCTAssertTrue(app.tables["blacklist.list"].waitForExistence(timeout: 5))
        let restoreBtn = app.buttons["恢复 电锯人"]
        XCTAssertTrue(restoreBtn.waitForExistence(timeout: 5))
        restoreBtn.tap()
        XCTAssertTrue(app.staticTexts["黑名单是空的"].waitForExistence(timeout: 5))

        app.tabBars.buttons["书架"].tap()
        app.buttons["我的书架"].tap()
        XCTAssertTrue(comic.waitForExistence(timeout: 5))
    }
}
