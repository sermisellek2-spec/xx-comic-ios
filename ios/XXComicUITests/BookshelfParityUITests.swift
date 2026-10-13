import XCTest
import UIKit

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

    func testLocalImportDragKeepsItsEdgeAndPositionThroughLayoutRotationAndRelaunch() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        for dark in [false, true] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--epub-fixtures", dark ? "--dark-mode" : "--light-mode"]
            app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
            app.launch()
            XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 15)); app.buttons["本地书架"].tap()
            let bubble = app.buttons["bookshelf.import"]
            XCTAssertTrue(bubble.waitForExistence(timeout: 10)); XCTAssertTrue(bubble.isHittable)
            let window = app.windows.firstMatch.frame
            bubble.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.45)))
            let snapped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                abs(bubble.frame.minX - window.minX - 16) < 1 && bubble.isHittable
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [snapped], timeout: 5), .completed)
            XCTAssertFalse(app.buttons["EPUB 漫画"].exists, "Dragging must not open the import menu")
            let saved = bubble.frame
            app.buttons["我的书架"].tap(); app.buttons["本地书架"].tap()
            app.buttons["bookshelf.layout"].tap()
            XCTAssertEqual(bubble.frame.minX, saved.minX, accuracy: 1)
            XCTAssertEqual(bubble.frame.minY, saved.minY, accuracy: 1)
            for landscape in [false, true] {
                XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let frame = app.windows.firstMatch.frame
                    return (frame.width > frame.height) == landscape && frame.contains(bubble.frame)
                        && bubble.isHittable && bubble.frame.maxY <= app.tabBars.firstMatch.frame.minY - 19
                }, object: app)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
                let frame = app.windows.firstMatch.frame
                XCTAssertTrue(frame.contains(bubble.frame)); XCTAssertTrue(bubble.isHittable)
                XCTAssertLessThan(bubble.frame.midX, frame.midX)
                XCTAssertLessThanOrEqual(bubble.frame.maxY, app.tabBars.firstMatch.frame.minY - 20 + 1)
                let prefix = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
                let name = "\(prefix)_\(landscape ? "landscape" : "portrait")_\(dark ? "dark" : "light")_local_import_bubble"
                let screenshot = XCUIScreen.main.screenshot()
                let shot = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: "public.png")
                shot.name = name; shot.lifetime = .keepAlways; add(shot)
                let record: [String: Any] = ["scene": name, "fixtureID": "real-image-epub-bubble-v1",
                    "appFrame": ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)],
                    "screenScale": Double(UIScreen.main.scale), "rasterPixelSize": [screenshot.image.cgImage?.width ?? 0, screenshot.image.cgImage?.height ?? 0],
                    "preferredContentSizeCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
                    "capturedAtUTC": ISO8601DateFormatter().string(from: Date()), "accessibilitySnapshot": app.debugDescription,
                    "steps": "Actual local bookshelf import-button drag, tab and layout changes, rotation; genuine image-only EPUB fixtures"]
                let proof = XCTAttachment(data: try JSONSerialization.data(withJSONObject: record, options: .sortedKeys), uniformTypeIdentifier: "public.json")
                proof.name = "provenance-" + name; proof.lifetime = .keepAlways; add(proof)
            }
            XCUIDevice.shared.orientation = .portrait
            let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
            app.terminate(); app.launch()
            XCTAssertTrue(app.buttons["本地书架"].waitForExistence(timeout: 15)); app.buttons["本地书架"].tap()
            XCTAssertTrue(bubble.waitForExistence(timeout: 10)); XCTAssertTrue(bubble.isHittable)
            XCTAssertEqual(bubble.frame.minX, saved.minX, accuracy: 1)
            XCTAssertEqual(bubble.frame.minY, saved.minY, accuracy: 1)
            bubble.tap()
            XCTAssertTrue(app.buttons["EPUB 漫画"].waitForExistence(timeout: 5))
            app.buttons["取消"].tap(); XCTAssertTrue(bubble.isHittable)
            app.terminate()
        }
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
