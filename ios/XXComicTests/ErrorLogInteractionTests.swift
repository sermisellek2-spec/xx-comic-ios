import XCTest
import UIKit
import ComicCore
@testable import XXComic

@MainActor
final class ErrorLogInteractionTests: XCTestCase {
    func testCopyWritesTheStoredRedactedLogAndKeepsExportAvailable() throws {
        let store = ErrorLogStore(userDefaults: nil)
        store.append(title: "复制验收", error: NSError(domain: "Fixture", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "文件校验失败\nAuthorization: Bearer TEST_AUTH_FIELD\nCookie: TEST_COOKIE_FIELD\ntoken=TEST_TOKEN_FIELD"]))
        let entry = try XCTUnwrap(store.entries().first)
        XCTAssertTrue(entry.fullText.contains("[REDACTED]"))
        for raw in ["TEST_AUTH_FIELD", "TEST_COOKIE_FIELD", "TEST_TOKEN_FIELD"] {
            XCTAssertFalse(entry.fullText.contains(raw))
        }
        let controller = ErrorLogDetailViewController(entry: entry)
        controller.loadViewIfNeeded()
        let copy = try XCTUnwrap(find("error.logs.copy", in: controller.view) as? UIButton)
        let export = try XCTUnwrap(find("error.logs.export", in: controller.view) as? UIButton)
        let feedback = try XCTUnwrap(find("error.logs.copy.feedback", in: controller.view) as? UILabel)
        let original = UIPasteboard.general.string
        defer { UIPasteboard.general.string = original }
        copy.sendActions(for: .touchUpInside)
        XCTAssertEqual(UIPasteboard.general.string, entry.fullText)
        XCTAssertEqual(feedback.text, "日志已复制")
        XCTAssertFalse(feedback.isHidden)
        XCTAssertTrue(export.isEnabled)
        XCTAssertNil(controller.presentedViewController)
    }

    private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
    }
}
