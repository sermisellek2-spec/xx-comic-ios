import XCTest

/// Record the actual failed screen in a portable format even when Xcode's
/// automatically generated diagnostic attachment is not a PNG.
class ParityUITestCase: XCTestCase {
    func waitForCacheCleanupResult(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let notice = app.staticTexts["cache.feedback"]
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@",
                                    "缓存已清理，收藏与本地漫画已保留", "已执行缓存清理，收藏与本地漫画已保留")
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: notice)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, file: file, line: line)
        XCTAssertTrue(app.buttons["确认清理"].isEnabled, file: file, line: line)
        XCTAssertFalse(notice.label.contains("请重试"), file: file, line: line)
    }

    func assertCacheLabelReflectsActualBytes(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let value = app.tables.cells["settings.cache"].staticTexts["settings.cache.value"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            value.exists && (value.value as? String)?.hasPrefix("memory=") == true
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, file: file, line: line)
        guard let raw = value.value as? String else { XCTFail("Missing actual cache byte measurement", file: file, line: line); return }
        let numbers = raw.components(separatedBy: "; ").map { $0.components(separatedBy: "=").last ?? "" }
        guard numbers.count == 2, let memory = Int64(numbers[0]), let disk = Int64(numbers[1]),
              memory >= 0, disk >= 0, memory <= Int64.max - disk else {
            XCTFail("Invalid cache byte measurement", file: file, line: line); return
        }
        let parts = value.label.split(separator: " ")
        let units: [String: Double] = ["B": 1, "KB": 1024, "MB": 1048576, "GB": 1073741824]
        guard parts.count == 2, let displayed = Double(parts[0]), let unit = units[String(parts[1])] else {
            XCTFail("Cache label must show measured bytes", file: file, line: line); return
        }
        let actual = Double(memory + disk)
        let expectedUnit: Double = actual < 1024 ? 1 : (actual < 1048576 ? 1024 : (actual < 1073741824 ? 1048576 : 1073741824))
        XCTAssertEqual(unit, expectedUnit, file: file, line: line)
        // The app displays one decimal in larger units; compare the underlying
        // real measurement, rather than pretending native index files use 0 B.
        XCTAssertLessThanOrEqual(abs(displayed * unit - actual), unit == 1 ? 0 : unit * 0.05 + 1, file: file, line: line)
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 || (testRun?.unexpectedExceptionCount ?? 0) > 0 {
            let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation,
                                           uniformTypeIdentifier: "public.png")
            attachment.name = "failure-screen"
            attachment.lifetime = .keepAlways
            add(attachment)
            let hierarchy = XCTAttachment(string: XCUIApplication().debugDescription)
            hierarchy.name = "failure-accessibility"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        try super.tearDownWithError()
    }
}
