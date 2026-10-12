import XCTest
@testable import XXComic

@MainActor
final class WebCacheCleanupTests: XCTestCase {
    func testUnusedBrowserCacheCleanupCompletesAndCanBeRepeatedWithoutLoadingAWebsite() async throws {
        let suite = "WebCacheCleanupTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = Mh18BrowserSession(defaults: defaults)
        for _ in 0..<2 {
            defaults.set(Date(), forKey: "mh18.verifiedAt")
            try await browser.clearCache()
            XCTAssertNil(defaults.object(forKey: "mh18.verifiedAt"))
            XCTAssertEqual(browser.status, "未验证")
        }
    }
}
