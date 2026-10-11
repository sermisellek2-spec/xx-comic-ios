import XCTest
import UIKit
@testable import XXComic

@MainActor
final class TestHostIsolationTests: XCTestCase {
    func testHostedUnitTestsDoNotBootstrapTheProductionApplication() throws {
        let delegate = try XCTUnwrap(UIApplication.shared.delegate as? AppDelegate)
        let root = try XCTUnwrap(delegate.window?.rootViewController)
        XCTAssertFalse(root is UITabBarController, "原生单元测试宿主不得启动正式站源、书架刷新或启动统计。")
        XCTAssertTrue(type(of: root) == UIViewController.self)
    }
}
