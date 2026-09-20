#if canImport(WebKit)
import XCTest
import WebKit
@testable import ComicCore

final class Mh18BrowserContentRulesTests: XCTestCase {
    @MainActor
    func testWebKitCompilesTheExactProductionNetworkRules() async throws {
        let encoded = try Mh18BrowserContentRules.encoded()
        let identifier = "mh18-rules-test-" + UUID().uuidString
        let store = WKContentRuleListStore.default()!
        let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encoded) { list, error in
                if let error { continuation.resume(throwing: error) }
                else if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: NSError(domain: "Mh18Rules", code: 1)) }
            }
        }
        XCTAssertEqual(list.identifier, identifier)
        store.removeContentRuleList(forIdentifier: identifier) { _ in }
    }
}
#endif
