import Foundation
import XCTest
@testable import ComicCore

final class DongmanLaSourceTests: XCTestCase {
    func testSearchCategoryDetailDirectoryAndAllReaderAreParsed() async throws {
        let transport = DongmanLaFakeTransport()
        let source = DongmanLaComicSource(transport: transport)

        let results = try await source.search(keyword: "海贼王", page: 1)
        XCTAssertEqual(results.first?.comicId, "dongmanla:5314")
        let searchUrl = await transport.lastUrl
        XCTAssertTrue(searchUrl?.contains("/manhua/so/%E6%B5%B7%E8%B4%BC%E7%8E%8B/1.html") == true)

        _ = try await source.category(filters: ["category": "jp"], page: 2)
        let catUrl = await transport.lastUrl
        XCTAssertTrue(catUrl?.hasSuffix("/manhua/japan/2.html") == true)

        let detail = try await source.detail(comicId: "dongmanla:5314")
        XCTAssertEqual(detail.summary.title, "海贼王")
        XCTAssertTrue(detail.chapters.isEmpty)
        let detailRequests = await transport.requests

        let chapters = try await source.chapters(comicId: detail.summary.comicId)
        let afterChaptersRequests = await transport.requests
        XCTAssertEqual(detailRequests, afterChaptersRequests, "应复用详情页 HTML 缓存不重复请求")
        XCTAssertEqual(chapters.first?.chapterId, "179802")

        let page = try await source.chapter(url: chapters[0].url)
        XCTAssertEqual(page.imageUrls.count, 2)
        let chapterUrl = await transport.lastUrl
        XCTAssertTrue(chapterUrl?.hasSuffix("/manhua/chapter/5314/179802/all.html") == true)
    }

    func testHunter44074KeepsAllThirtyImagesOutsideHDirectory() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "dongmanla-44074", withExtension: "html"))
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let source = DongmanLaComicSource(transport: DongmanLaStaticTransport(html: html))
        let page = try await source.chapter(url: "https://www.dongman.la/manhua/chapter/5329/44074/")
        XCTAssertEqual(page.chapterId, "44074")
        XCTAssertEqual(page.imageUrls.count, 30)
        XCTAssertEqual(page.imageUrls.first, "https://img.dongman.la/q/qzlr/klpkhy1/001.jpg")
        XCTAssertEqual(page.imageUrls.last, "https://img.dongman.la/q/qzlr/klpkhy1/030.jpg")
    }

    func testLazyDirectoryStillPreservesLatestChapterMetadata() {
        XCTAssertEqual(
            "第20话",
            DongmanLaComicSource.parseLatestChapter(
                comicId: "5329",
                html: "<a href='/manhua/chapter/5329/1/'>开始阅读</a><div id='chapterList'>"
                    + "<a href='/manhua/chapter/5329/20/'>第20话</a><a href='/manhua/chapter/5329/1/'>第1话</a></div>"
            )
        )
    }

    func testSourceConfigDefaultsAndFilterGroups() async throws {
        let def = try XCTUnwrap(SourceConfigDefaults.defaultConfig(for: "dongmanla"))
        XCTAssertEqual(def.id, "dongmanla")
        XCTAssertEqual(def.name, "动漫啦")
        XCTAssertEqual(def.domain, "www.dongman.la")
        XCTAssertEqual(def.filter("category.jp"), "/manhua/japan/")
        XCTAssertEqual(def.filter("category.genre.83"), "/manhua/class/83/")

        let source = DongmanLaComicSource(config: def, transport: DongmanLaFakeTransport())
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].key, "category")
        XCTAssertEqual(groups[0].options.count, 48)
        let healthy = await source.healthCheck()
        XCTAssertTrue(healthy)
    }
}

private actor DongmanLaFakeTransport: HTTPTransport {
    var lastUrl: String?
    var requests = 0

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests += 1
        let u = url.absoluteString
        lastUrl = u
        if u.contains("/chapter/") {
            return .html("<title>海贼王第1073话 - 动漫啦</title><img src=\"https://img.dongman.la/h/hzw/1073/0001.jpg\"><img src=\"https://img.dongman.la/h/hzw/1073/0002.jpg\">")
        }
        if u.contains("/detail/") {
            return .html("<h1 class=\"cy_title\">海贼王</h1><div class=\"cy_info_cover\"><img src=\"https://img.dongman.la/cover.jpg\"></div><div id=\"comic-description\">冒险漫画</div><a href=\"/manhua/chapter/5314/179802/\" title=\"第1073话\">第1073话</a>")
        }
        return .html("<div class=\"cy_list_mh\"><ul><li><a class=\"pic\" href=\"/manhua/detail/5314/\"><img src=\"https://img.dongman.la/cover.jpg\" alt=\"海贼王漫画\"></a></li><li class=\"title\"><a href=\"/manhua/detail/5314/\">海贼王</a></li><li class=\"zuozhe\">状态：连载中</li></ul></div>")
    }
}

private struct DongmanLaStaticTransport: HTTPTransport {
    let html: String
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        .html(html)
    }
}
