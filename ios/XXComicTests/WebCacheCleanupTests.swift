import XCTest
import WebKit
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

    func testExistingWebsiteCookieIsActuallyRemovedWithoutLoadingAWebsite() async throws {
        let suite = "WebCacheCleanupTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "fixture.invalid", .path: "/", .name: "cache-removal-probe",
            .value: "isolated-test-value", .expires: Date().addingTimeInterval(3600)
        ]))
        let store = WKWebsiteDataStore.default().httpCookieStore
        await store.setCookie(cookie)
        let before = await store.allCookies()
        XCTAssertTrue(before.contains { $0.name == cookie.name && $0.domain == cookie.domain })
        let browser = Mh18BrowserSession(defaults: defaults)
        try await browser.clearCache()
        let after = await store.allCookies()
        XCTAssertFalse(after.contains { $0.name == cookie.name && $0.domain == cookie.domain })
        try await browser.clearCache()
    }
}
