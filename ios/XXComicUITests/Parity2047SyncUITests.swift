import XCTest

final class Parity2047SyncUITests: ParityUITestCase {
    func testEmptySourcesOnboardingNavigatesFromDiscoverToSourceManagement() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-empty-sources", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["发现"].waitForExistence(timeout: 10))
        app.tabBars.buttons["发现"].tap()

        XCTAssertTrue(app.staticTexts["还没有站源"].waitForExistence(timeout: 5))
        let addBtn = app.buttons["discover.add.sources"]
        XCTAssertTrue(addBtn.exists)
        XCTAssertTrue(addBtn.isHittable)
        addBtn.tap()

        let emptyTitle = app.staticTexts["source.settings.empty.title"]
        XCTAssertTrue(emptyTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(emptyTitle.label, "还没有站源")
        let quickSub = app.buttons["source.settings.empty.quickSubscribe"]
        XCTAssertTrue(quickSub.exists)
        XCTAssertTrue(quickSub.isHittable)
    }

    func testDetailUnfavoriteShowsRemToastAndUndoRestoresFavorite() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10))
        app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 10))
        comic.tap()

        let favButton = app.buttons["detail.favorite"]
        XCTAssertTrue(favButton.waitForExistence(timeout: 5))
        XCTAssertEqual(favButton.label, "取消收藏")

        favButton.tap()
        XCTAssertEqual(favButton.label, "收藏")

        let toastMsg = app.staticTexts["rem.toast.message"]
        XCTAssertTrue(toastMsg.waitForExistence(timeout: 5))
        XCTAssertEqual(toastMsg.label, "已移出书架")

        let undoButton = app.buttons["rem.toast.action"]
        XCTAssertTrue(undoButton.exists)
        XCTAssertTrue(undoButton.isHittable)
        undoButton.tap()

        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "取消收藏"), object: favButton)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }

    func testReaderComfortKeepScreenAndBrightnessControlsPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-reader-original", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10))
        app.buttons["我的书架"].tap()
        let comic = app.collectionViews.cells["电锯人"]
        XCTAssertTrue(comic.waitForExistence(timeout: 10))
        comic.tap()

        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 10))
        app.buttons["reader.settings"].tap()

        let content = app.scrollViews["reader.settings.content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))

        let followSwitch = app.switches["reader.brightness.follow.system"]
        for _ in 0..<6 where !followSwitch.isHittable { content.swipeUp() }
        XCTAssertTrue(followSwitch.isHittable)
        XCTAssertEqual(followSwitch.value as? String, "1")
        XCTAssertFalse(app.sliders["reader.brightness.slider"].isHittable)

        followSwitch.tap()
        XCTAssertEqual(followSwitch.value as? String, "0")
        XCTAssertTrue(app.sliders["reader.brightness.slider"].waitForExistence(timeout: 5))

        let dimSwitch = app.switches["reader.brightness.dim.enabled"]
        for _ in 0..<6 where !dimSwitch.isHittable { content.swipeUp() }
        XCTAssertTrue(dimSwitch.isHittable)
        XCTAssertEqual(dimSwitch.value as? String, "0")
        dimSwitch.tap()
        XCTAssertEqual(dimSwitch.value as? String, "1")
        XCTAssertTrue(app.sliders["reader.brightness.dim.slider"].waitForExistence(timeout: 5))

        let keep30 = app.buttons["reader.keep.screen.30"]
        for _ in 0..<6 where !keep30.isHittable { content.swipeUp() }
        XCTAssertTrue(keep30.isHittable)
        keep30.tap()
        XCTAssertTrue(keep30.isSelected)

        app.buttons["reader.settings.close"].tap()
        app.terminate()
        app.launch()

        XCTAssertTrue(app.buttons["我的书架"].waitForExistence(timeout: 10))
        app.buttons["我的书架"].tap()
        XCTAssertTrue(app.collectionViews.cells["电锯人"].waitForExistence(timeout: 10))
        app.collectionViews.cells["电锯人"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 10))
        app.buttons["reader.settings"].tap()

        XCTAssertEqual(app.switches["reader.brightness.follow.system"].value as? String, "0")
        XCTAssertEqual(app.switches["reader.brightness.dim.enabled"].value as? String, "1")
        XCTAssertTrue(app.buttons["reader.keep.screen.30"].isSelected)
    }
}
