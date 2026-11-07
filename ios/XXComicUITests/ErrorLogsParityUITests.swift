import XCTest
import UIKit

final class ErrorLogsParityUITests: ParityUITestCase {
    func testLogDetailsAreRedactedCopyIsUsableAndCancelledClearPreservesTheLog() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--matrix-fixtures", "--matrix-error-log-fixture", "--light-mode"]
        app.launchEnvironment["XXCOMIC_UI_TEST_SESSION"] = UUID().uuidString
        app.launch(); XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        let entry = app.tables.cells.containing(.staticText, identifier: "错误日志").firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        let row = app.tables["error.logs.list"].cells.containing(.staticText, identifier: "验收导入错误").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let detail = app.textViews["error.logs.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let content = detail.value as? String ?? ""
        XCTAssertTrue(content.contains("文件校验失败")); XCTAssertTrue(content.contains("[REDACTED]"))
        for field in ["TEST_AUTH_FIELD", "TEST_COOKIE_FIELD", "TEST_TOKEN_FIELD"] { XCTAssertFalse(content.contains(field)) }
        app.buttons["error.logs.copy"].tap(); XCTAssertTrue(app.staticTexts["日志已复制"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["error.logs.copy.feedback"].isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["error.logs.export"].isHittable)
        app.buttons["error.logs.export"].tap()
        dismissSystemShareUI(in: app)
        XCTAssertTrue(app.buttons["error.logs.copy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["error.logs.copy.feedback"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["error.logs.more"].tap(); app.buttons["导出全部日志"].tap()
        dismissSystemShareUI(in: app)
        app.buttons["error.logs.more"].tap(); app.buttons["清空错误日志"].tap()
        XCTAssertTrue(app.alerts["清空错误日志"].waitForExistence(timeout: 5)); app.alerts["清空错误日志"].buttons["取消"].tap()
        XCTAssertTrue(row.exists)
        app.buttons["error.logs.more"].tap(); app.buttons["清空错误日志"].tap()
        let clearAlert = app.alerts["清空错误日志"]
        XCTAssertTrue(clearAlert.waitForExistence(timeout: 5))
        for _ in 0..<3 where clearAlert.exists {
            let confirmButton = clearAlert.buttons["清空"]
            if confirmButton.exists && confirmButton.isHittable {
                confirmButton.tap()
            }
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: clearAlert)
            if XCTWaiter.wait(for: [gone], timeout: 1.5) == .completed { break }
        }
        XCTAssertTrue(app.staticTexts["error.logs.empty"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10)); app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.staticTexts["error.logs.empty"].waitForExistence(timeout: 5))
    }

    private func dismissSystemShareUI(in app: XCUIApplication) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let popoverDismiss = app.otherElements["PopoverDismissRegion"].firstMatch
            XCTAssertTrue(popoverDismiss.waitForExistence(timeout: 5), "The system share popover must expose its dismiss region on iPad")
            popoverDismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.85)).tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: popoverDismiss)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        } else {
            let close = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", ["Close", "关闭", "Cancel", "取消"], ["Close", "关闭", "Cancel", "取消", "close-button", "header.closeButton"])).firstMatch
            let activityListView = app.otherElements["ActivityListView"]
            if close.waitForExistence(timeout: 5) && close.isHittable {
                close.tap()
            } else if activityListView.waitForExistence(timeout: 3) {
                activityListView.swipeDown(velocity: .fast)
            } else {
                app.swipeDown()
            }
            let export = app.buttons["error.logs.export"]
            let more = app.buttons["error.logs.more"]
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in export.isHittable || more.isHittable }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        }
    }
}
