import XCTest
@testable import ComicCore

final class HiperdexSourceTests: XCTestCase {
    private let cards = """
    <main><div class="page-listing-item manga-item"><a href="https://hiperdex.com/manga/star-sea/"><img data-src="//img.test/a.jpg?a=1&amp;b=2" alt="fallback"></a><h3><a>Star &amp; Sea</a></h3><a href="/manga/star-sea/chapter-9/">Chapter 9</a></div>
    <div class="manga__item"><a href="/manga/star-sea/"><img src="/duplicate.jpg"></a><h2><a>Duplicate</a></h2></div>
    <div class="manga-item"><a href="/manga/moon/"><img data-lazy-src="/moon.webp"></a><h2><a>Moon</a></h2></div></main>
    """

    func testLatestSearchCategoryAndFiltersPreserveAndroidURLsAndOrder() async throws {
        let transport = HiperdexTransport([
            "https://hiperdex.com/manga/?m_orderby=latest&paged=2": cards,
            "https://hiperdex.com/?s=star%20%26%20sea&post_type=wp-manga&paged=3": cards,
            "https://hiperdex.com/manga/webtoon/page/4/": cards
        ])
        let source = HiperdexComicSource(transport: transport)
        let latest = try await source.latest(page: 2)
        XCTAssertEqual(latest, [
            .init(sourceId: "hiperdex", comicId: "hiperdex:star-sea", title: "Star & Sea", coverUrl: "https://img.test/a.jpg?a=1&b=2", subtitle: "Chapter 9"),
            .init(sourceId: "hiperdex", comicId: "hiperdex:moon", title: "Moon", coverUrl: "https://hiperdex.com/moon.webp")
        ])
        let searched = try await source.search(keyword: " star & sea ", page: 3)
        let categorized = try await source.category(filters: ["region": "all", "state": "webtoon"], page: 4)
        let filters = try await source.filterGroups()
        XCTAssertEqual(searched, latest)
        XCTAssertEqual(categorized, latest)
        XCTAssertEqual(filters, [
            .init(key: "region", label: "题材", options: [
                .init(label: "全部", value: "all"), .init(label: "Manhwa", value: "manhwa"),
                .init(label: "Webtoon", value: "webtoon"), .init(label: "Romance", value: "romance"),
                .init(label: "Drama", value: "drama")
            ])
        ])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].headers["Referer"], "https://hiperdex.com/")
        XCTAssertTrue(requests[0].headers["User-Agent"]?.contains("Chrome/124.0.0.0") == true)
    }

    func testDetailCatalogAndReaderDecodeEntitiesWithoutPreloadingCatalog() async throws {
        let detailHTML = """
        <meta property="og:title" content="Star &amp; Sea - HiperDEX"><meta property="og:image" content="//img.test/cover.jpg"><meta property="og:description" content="A &hellip; tale">
        <div>Author <a>Ann &amp; Bob</a></div><div>Status <a>Ongoing</a></div>
        <a href="https://hiperdex.com/manga/star-sea/chapter-10/">Chapter 10</a>
        <a href="/manga/star-sea/chapter-2/">Chapter &#35;2</a>
        <a href="/manga/star-sea/chapter-2/">Duplicate</a>
        """
        let readerHTML = """
        <h1>Chapter &#35;10</h1><img src="/cover.jpg"><div class="reading-content">
        <img data-src="//cdn.test/1.jpg?a=1&amp;b=2"><img data-lazy-src="/2.webp"><img src="//cdn.test/1.jpg?a=1&amp;b=2"><img src="/logo.png">
        </div><div class="comments-area"><img src="/comment.jpg"></div>
        """
        let transport = HiperdexTransport([
            "https://hiperdex.com/manga/star-sea/": detailHTML,
            "https://hiperdex.com/manga/star-sea/chapter-10/": readerHTML
        ])
        let source = HiperdexComicSource(transport: transport)
        let detail = try await source.detail(comicId: "hiperdex:https://old/manga/star-sea/ignored")
        XCTAssertEqual(detail.summary, .init(sourceId: "hiperdex", comicId: "hiperdex:star-sea", title: "Star & Sea", coverUrl: "https://img.test/cover.jpg", subtitle: "Chapter 10"))
        XCTAssertEqual(detail.author, "Ann & Bob")
        XCTAssertEqual(detail.status, "Ongoing")
        XCTAssertEqual(detail.description, "A … tale")
        XCTAssertEqual(detail.latestChapter, "Chapter 10")
        XCTAssertEqual(detail.chapters, [])
        let detailRequestCount = await transport.requests.count
        XCTAssertEqual(detailRequestCount, 1)
        let chapters = try await source.chapters(comicId: "hiperdex:star-sea")
        XCTAssertEqual(chapters, [
            .init(chapterId: "chapter-10", title: "Chapter 10", url: "https://hiperdex.com/manga/star-sea/chapter-10/", chapterSlot: 0),
            .init(chapterId: "chapter-2", title: "Chapter #2", url: "https://hiperdex.com/manga/star-sea/chapter-2/", chapterSlot: 1)
        ])
        let page = try await source.chapter(url: "/manga/star-sea/chapter-10/")
        XCTAssertEqual(page.title, "Chapter #10")
        XCTAssertEqual(page.chapterId, "/manga/star-sea/chapter-10/")
        XCTAssertEqual(page.imageUrls, ["https://cdn.test/1.jpg?a=1&b=2", "https://hiperdex.com/2.webp"])
    }

    func testValidEmptyListDiffersFromErrorShellAndTransportFailuresPropagate() async throws {
        let empty = HiperdexComicSource(transport: HiperdexTransport(["https://hiperdex.com/manga/?m_orderby=latest": "<main class='c-page-content'><div class='c-tabs-item__content'></div></main>"]))
        let emptyItems = try await empty.latest(page: 1)
        XCTAssertEqual(emptyItems, [])
        let shell = HiperdexComicSource(transport: HiperdexTransport(["https://hiperdex.com/manga/?m_orderby=latest": "<html><title>Sign in</title><h1>Rate limited</h1></html>"]))
        await XCTAssertHiperdexThrows(try await shell.latest(page: 1)) { XCTAssertNotNil($0 as? HiperdexSourceError) }
        let status = HiperdexComicSource(transport: HiperdexTransport(["https://hiperdex.com/manga/?m_orderby=latest": cards], status: 503))
        await XCTAssertHiperdexThrows(try await status.latest(page: 1)) { XCTAssertEqual($0 as? HTTPTransportError, .invalidStatusCode(503)) }
        let cancelled = HiperdexComicSource(transport: HiperdexCancelledTransport())
        await XCTAssertHiperdexThrows(try await cancelled.latest(page: 1)) { XCTAssertTrue($0 is CancellationError) }
    }

    func testCatalogDistinguishesRecognizedEmptyDetailFromErrorHeading() async throws {
        let source = HiperdexComicSource(transport: HiperdexTransport([
            "https://hiperdex.com/manga/empty/": "<meta property=\"og:title\" content=\"Empty - HiperDEX\"><div class=\"chapter-list\"></div>",
            "https://hiperdex.com/manga/bad/": "<html><h1>Rate limited</h1></html>"
        ]))
        let empty = try await source.chapters(comicId: "empty")
        XCTAssertEqual(empty, [])
        await XCTAssertHiperdexThrows(try await source.chapters(comicId: "bad")) { XCTAssertNotNil($0 as? HiperdexSourceError) }
    }

    func testDetailRejectsErrorHeadingAndStripsSuffixAfterH1Fallback() async throws {
        let source = HiperdexComicSource(transport: HiperdexTransport([
            "https://hiperdex.com/manga/fallback/": "<h1>Fallback &amp; Title - HiperDEX</h1><div class='summary__content'>Description</div>",
            "https://hiperdex.com/manga/bad/": "<html><h1>Rate limited</h1></html>"
        ]))
        let detail = try await source.detail(comicId: "fallback")
        XCTAssertEqual(detail.summary.title, "Fallback & Title")
        await XCTAssertHiperdexThrows(try await source.detail(comicId: "bad")) { XCTAssertNotNil($0 as? HiperdexSourceError) }
    }

    func testFallbackLinksRunWhenRecognizedCardBlocksProduceNoItems() async throws {
        let html = "<main class='c-page-content'><div class=\"manga-item\"><span>broken card</span></div></main><a href=\"/manga/fallback/\">Fallback &amp; Name</a>"
        let source = HiperdexComicSource(transport: HiperdexTransport(["https://hiperdex.com/manga/?m_orderby=latest": html]))
        let items = try await source.latest(page: 1)
        XCTAssertEqual(items, [.init(sourceId: "hiperdex", comicId: "hiperdex:fallback", title: "Fallback & Name")])
    }
}

private struct HiperdexRequest: Sendable { let url: String; let headers: [String: String] }
private actor HiperdexTransport: HTTPTransport {
    let responses: [String: String]; let status: Int; var requests: [HiperdexRequest] = []
    init(_ responses: [String: String], status: Int = 200) { self.responses = responses; self.status = status }
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(.init(url: url.absoluteString, headers: headers))
        guard let html = responses[url.absoluteString] else { throw URLError(.badURL) }
        return .init(data: Data(html.utf8), statusCode: status)
    }
}
private struct HiperdexCancelledTransport: HTTPTransport { func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse { throw CancellationError() } }
private func XCTAssertHiperdexThrows<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected throw", file: file, line: line) } catch { handler(error) }
}
