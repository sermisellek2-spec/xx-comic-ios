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
        // Close the real system share UI using its own controls or gesture.
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "关闭"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "The system share controller must expose its real close control")
        XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertTrue(app.buttons["error.logs.copy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["error.logs.copy.feedback"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["error.logs.more"].tap(); app.buttons["导出全部日志"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5)); XCTAssertTrue(close.isHittable); close.tap()
        app.buttons["error.logs.more"].tap(); app.buttons["清空错误日志"].tap()
        XCTAssertTrue(app.alerts["清空错误日志"].waitForExistence(timeout: 5)); app.alerts["清空错误日志"].buttons["取消"].tap()
        XCTAssertTrue(row.exists)
        app.buttons["error.logs.more"].tap(); app.buttons["清空错误日志"].tap(); app.alerts["清空错误日志"].buttons["清空"].tap()
        XCTAssertTrue(app.staticTexts["error.logs.empty"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.tabBars.buttons["设置"].tap(); entry.tap()
        XCTAssertTrue(app.staticTexts["error.logs.empty"].waitForExistence(timeout: 5))
    }
}
