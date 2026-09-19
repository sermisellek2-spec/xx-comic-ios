import XCTest
@testable import ComicCore

final class D5d6SourceTests: XCTestCase {
    private let cards = """
    <ul class="cart-list"><li><div class="cart-item"><a class="cart-cover" href="/jiujiucomic_42/"><img data-original="//img.test/a.jpg?a=1&amp;b=2" alt="星&amp;海"></a><div class="cart-info"><p><a>星&amp;海</a></p></div><span class="new-chapter">第9话</span></div></li>
    <li><div class="cart-item"><a href="/jiujiucomic_42/"><img alt="重复"></a><div class="cart-info"><p><a>重复</a></p></div></div></li>
    <li><div class="cart-item"><a class="cart-cover" href="/jiujiucomic_7/"><img data-src="/b.webp" alt="月"></a><div class="cart-info"><p><a>月</a></p></div></div></li></ul>
    """

    func testLatestSearchFiltersAndCategoryKeepRequestsFallbackAndOrdering() async throws {
        let index = """
        <a href="/jiujiucate_jiujiuquanbu_allvisit_0_1/">全部</a>
        <a href="/jiujiucate_jiujiudalu_allvisit_0_1/">大陆</a>
        <a href="https://www.d5d6.com/jiujiucate_jiujiuriben_allvisit_0_1/">日本</a>
        <a href="/jiujiucate_jiujiudalu_allvisit_1_2/">大陆</a>
        """
        let transport = D5d6Transport([
            "https://www.d5d6.com/jiujiucate_jiujiuquanbu_allvisit_0_2/": .text(cards),
            "https://www.d5d6.com/search/%E6%98%9F+%26+%7E*/": .text(cards),
            "https://www.d5d6.com/jiujiucate_quanbu/": .text(index),
            "https://www.d5d6.com/jiujiucate_jiujiuriben_allvisit_2_3/": .text(cards)
        ])
        let source = D5d6ComicSource(transport: transport)
        let latest = try await source.latest(page: 2)
        XCTAssertEqual(latest.map(\.comicId), ["d5d6:42", "d5d6:7"])
        XCTAssertEqual(latest.map(\.title), ["星&海", "月"])
        XCTAssertEqual(latest[0].coverUrl, "https://img.test/a.jpg?a=1")
        XCTAssertEqual(latest[1].coverUrl, "https://www.d5d6.com/b.webp")
        let searched = try await source.search(keyword: " 星 & ~* ", page: 1)
        XCTAssertEqual(searched, latest)
        let skipped = try await source.search(keyword: "ignored", page: 2)
        XCTAssertEqual(skipped, [])
        let categories = try await source.categories()
        XCTAssertEqual(categories, ["大陆", "日本"])
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups, [
            .init(key: "category", label: "题材", options: [.init(label: "全部", value: "all"), .init(label: "大陆", value: "jiujiudalu"), .init(label: "日本", value: "jiujiuriben")]),
            .init(key: "state", label: "状态", options: [.init(label: "全部", value: "all"), .init(label: "连载中", value: "serial"), .init(label: "已完成", value: "pub")])
        ])
        let category = try await source.category(filters: ["category": "jiujiuriben", "state": "pub"], page: 3)
        XCTAssertEqual(category, latest)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests[0].headers["Referer"], "https://www.d5d6.com/")
    }

    func testDetailCatalogReaderAndEmptySearchMatchAndroidContracts() async throws {
        let detail = """
        <div class="cover-box"><img data-original="/cover.jpg"></div>
        <div class="article-info-item"><h1 class="title">星&amp;海</h1>
        <p><span class="tag">作者：</span>甲&amp;乙</p>
        <p><span class="tag">简介：</span>故事 &hellip; 继续</p>
        <p><span class="tag">最新章节：</span><a>第10话</a></p><i class="tag-serialize-doing"></i><div class="mt20"></div></div>
        <ul class="chapter-list"><li><a href="10.html">第10话</a></li><li><a href="/jiujiucomic_42/2.html">第2话</a></li><li><a href="10.html">重复</a></li></ul>
        """
        let reader = "<h1>第10话</h1><div class=\"comicpage\"><img data-original=\"/1.jpg\"><img data-src=\"//img.test/2.webp\"><img src=\"/logo.png\"><img src=\"/1.jpg\"></div>"
        let emptySearch = "<div>搜索《无》结果为空，以下是为您推荐的热门作品</div>" + cards
        let transport = D5d6Transport([
            "https://www.d5d6.com/jiujiucomic_42/": .text(detail),
            "https://www.d5d6.com/jiujiucomic_42/10.html": .text(reader),
            "https://www.d5d6.com/search/%E6%97%A0/": .text(emptySearch)
        ])
        let source = D5d6ComicSource(transport: transport)
        let item = try await source.detail(comicId: "d5d6:https://old/jiujiucomic_42/")
        XCTAssertEqual(item.summary, .init(sourceId: "d5d6", comicId: "d5d6:42", title: "星&海", coverUrl: "https://www.d5d6.com/cover.jpg", subtitle: "第10话"))
        XCTAssertEqual(item.author, "甲&乙")
        XCTAssertEqual(item.status, "连载中")
        XCTAssertEqual(item.description, "故事 … 继续")
        XCTAssertEqual(item.chapters, [])
        let detailRequestCount = await transport.count()
        XCTAssertEqual(detailRequestCount, 1)
        let chapters = try await source.chapters(comicId: "d5d6:42")
        XCTAssertEqual(chapters, [.init(chapterId: "10", title: "第10话", url: "https://www.d5d6.com/jiujiucomic_42/10.html", chapterSlot: 0), .init(chapterId: "2", title: "第2话", url: "https://www.d5d6.com/jiujiucomic_42/2.html", chapterSlot: 1)])
        let page = try await source.chapter(url: chapters[0].url)
        XCTAssertEqual(page.imageUrls, ["https://www.d5d6.com/1.jpg", "https://img.test/2.webp"])
        let emptySearchResult = try await source.search(keyword: "无", page: 1)
        XCTAssertEqual(emptySearchResult, [])
    }

    func testValidEmptyContainersDifferFromErrorsAndTransportFailuresPropagate() async throws {
        let valid = D5d6ComicSource(transport: D5d6Transport([
            "https://www.d5d6.com/jiujiucate_jiujiuquanbu_allvisit_0_1/": .text("<ul class='cart-list'></ul>"),
            "https://www.d5d6.com/jiujiucomic_42/empty.html": .text("<h1>空章节</h1><div class='comicpage'></div>")
        ]))
        let emptyLatest = try await valid.latest(page: 1)
        let emptyChapter = try await valid.chapter(url: "/jiujiucomic_42/empty.html")
        XCTAssertEqual(emptyLatest, [])
        XCTAssertEqual(emptyChapter.imageUrls, [])
        let shell = D5d6ComicSource(transport: D5d6Transport(["https://www.d5d6.com/jiujiucate_jiujiuquanbu_allvisit_0_1/": .text("<html><h1>Bad gateway</h1></html>")]))
        await XCTAssertD5d6Throws(try await shell.latest(page: 1)) { XCTAssertNotNil($0 as? D5d6SourceError) }
        let status = D5d6ComicSource(transport: D5d6Transport(["https://www.d5d6.com/jiujiucate_jiujiuquanbu_allvisit_0_1/": .text(cards, status: 503)]))
        await XCTAssertD5d6Throws(try await status.latest(page: 1)) { XCTAssertEqual($0 as? HTTPTransportError, .invalidStatusCode(503)) }
        let cancelled = D5d6ComicSource(transport: D5d6CancelledTransport())
        await XCTAssertD5d6Throws(try await cancelled.latest(page: 1)) { XCTAssertTrue($0 is CancellationError) }
    }

    func testCatalogAndCoverFallbackDistinguishSiteDetailFromErrorHeading() async throws {
        let source = D5d6ComicSource(transport: D5d6Transport([
            "https://www.d5d6.com/jiujiucomic_8/": .text("<div class='article-info-item'><h1 class='title'>星&amp;海</h1><div class='mt20'></div></div><img alt='星&海' src='/fallback.jpg'><ul class='chapter-list'></ul>"),
            "https://www.d5d6.com/jiujiucomic_9/": .text("<html><h1>Bad gateway</h1></html>")
        ]))
        let detail = try await source.detail(comicId: "8")
        XCTAssertEqual(detail.summary.coverUrl, "https://www.d5d6.com/fallback.jpg")
        let empty = try await source.chapters(comicId: "8")
        XCTAssertEqual(empty, [])
        await XCTAssertD5d6Throws(try await source.chapters(comicId: "9")) { XCTAssertNotNil($0 as? D5d6SourceError) }
    }

    func testDefaultGBKResponseDecodesChineseCards() async throws {
        var data = Data("<ul class='cart-list'><li><div class='cart-item'><a class='cart-cover' href='/jiujiucomic_6/'><img alt='".utf8)
        data.append(contentsOf: [0xC2, 0xFE, 0xBB, 0xAD]) // 漫画 in GBK
        data.append(Data("'></a><div class='cart-info'><p><a>".utf8))
        data.append(contentsOf: [0xC2, 0xFE, 0xBB, 0xAD])
        data.append(Data("</a></p></div></div></li></ul>".utf8))
        let url = "https://www.d5d6.com/jiujiucate_jiujiuquanbu_allvisit_0_1/"
        let items = try await D5d6ComicSource(transport: D5d6Transport([url: .init(data: data, statusCode: 200)])).latest(page: 1)
        XCTAssertEqual(items.map(\.title), ["漫画"])
    }

    func testResponseHeaderCharsetTakesPriority() async throws {
        let body = "<ul class='cart-list'><li><div class='cart-item'><a class='cart-cover' href='/jiujiucomic_10/'><img alt='Café'></a><div class='cart-info'><p><a>Café</a></p></div></div></li></ul>"
        let response = HTTPResponse(data: body.data(using: .isoLatin1)!, statusCode: 200, textEncodingName: "iso-8859-1")
        let url = "https://www.d5d6.com/jiujiucate_jiujiuquanbu_allvisit_0_1/"
        let items = try await D5d6ComicSource(transport: D5d6Transport([url: response])).latest(page: 1)
        XCTAssertEqual(items.map(\.title), ["Café"])
    }

    func testMissingCharsetDefaultsToGBKEvenWhenBytesAreValidUTF8() async throws {
        var data = Data("<ul class='cart-list'><li><div class='cart-item'><a class='cart-cover' href='/jiujiucomic_11/'><img alt='".utf8)
        data.append(contentsOf: [0xC2, 0xA2]) // UTF-8: ¢; GBK: 垄
        data.append(Data("'></a><div class='cart-info'><p><a>".utf8))
        data.append(contentsOf: [0xC2, 0xA2])
        data.append(Data("</a></p></div></div></li></ul>".utf8))
        let url = "https://www.d5d6.com/jiujiucate_jiujiuquanbu_allvisit_0_1/"
        let items = try await D5d6ComicSource(transport: D5d6Transport([url: .init(data: data, statusCode: 200)])).latest(page: 1)
        XCTAssertEqual(items.map(\.title), ["垄"])
    }
}

private struct D5d6Request: Sendable { let url: String; let headers: [String: String] }
private actor D5d6Transport: HTTPTransport {
    let responses: [String: HTTPResponse]; var requests: [D5d6Request] = []
    init(_ responses: [String: HTTPResponse]) { self.responses = responses }
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse { requests.append(.init(url: url.absoluteString, headers: headers)); guard let response = responses[url.absoluteString] else { throw URLError(.badURL) }; return response }
    func count() -> Int { requests.count }
}
private extension HTTPResponse { static func text(_ body: String, status: Int = 200) -> Self { .init(data: Data(body.utf8), statusCode: status, textEncodingName: "utf-8") } }
private struct D5d6CancelledTransport: HTTPTransport { func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse { throw CancellationError() } }
private func XCTAssertD5d6Throws<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void, file: StaticString = #filePath, line: UInt = #line) async { do { _ = try await expression(); XCTFail("Expected throw", file: file, line: line) } catch { handler(error) } }
