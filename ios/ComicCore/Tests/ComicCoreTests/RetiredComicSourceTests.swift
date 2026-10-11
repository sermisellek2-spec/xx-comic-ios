import XCTest
@testable import ComicCore

final class RetiredComicSourceTests: XCTestCase {
    func testRetiredSourcesKeepTheirIdentityAndRejectNewSearchAndReading() async throws {
        for (id, name) in [("baozimh", "包子漫画（已移除）"), ("mhua5", "漫画屋（已下线）")] {
            let source = RetiredComicSource(id: id, name: name)
            XCTAssertEqual(source.id, id)
            XCTAssertFalse(source.supportsSearch)
            do {
                _ = try await source.search(keyword: "旧收藏", page: 1)
                XCTFail("A retired adapter must not expose new search results")
            } catch {
                XCTAssertEqual(error as? RetiredSourceError, .unavailable(name))
            }
            do {
                _ = try await source.chapter(url: "https://old.example/1")
                XCTFail("A retired adapter must not silently claim an empty readable chapter")
            } catch {
                XCTAssertEqual(error as? RetiredSourceError, .unavailable(name))
            }
        }
    }
}
