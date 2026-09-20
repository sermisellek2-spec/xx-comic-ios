import Foundation
import XCTest
@testable import ComicCore

private let mh18Card = #"<a href="/manga/hero-story/1"><img src="https://img.18mh.org/a.webp"><h3 class="cardtitle">hero-story</h3></a>"#

final class Mh18SourceTests: XCTestCase {
    func testCatalogMarkerRequiresCompleteCard() {
        XCTAssertTrue(Mh18ComicSource.hasCatalogMarker(mh18Card))
        XCTAssertFalse(Mh18ComicSource.hasCatalogMarker("<h3 class='cardtitle'>漫画</h3>"))
        XCTAssertFalse(Mh18ComicSource.hasCatalogMarker("<title>Just a moment</title>"))
    }

    func testLatestRoutesDedupeSlugFallbackAndHeaders() async throws {
        let transport = Mh18Transport(["https://18mh.org/manga/page/2": response(mh18Card + mh18Card)])
        let source = Mh18ComicSource(transport: transport)
        let cards = try await source.latest(page: 2)
        XCTAssertEqual(cards, [.init(sourceId: "mh18", comicId: "mh18:hero-story", title: "hero story", coverUrl: "https://img.18mh.org/a.webp")])
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.1["Referer"], "https://18mh.org/")
        XCTAssertTrue(requests.first?.1["User-Agent"]?.contains("Windows NT 10.0") == true)
        XCTAssertTrue(requests.first?.1["User-Agent"]?.contains("Chrome/124.0.0.0") == true)
    }

    func testSearchUsesJavaFormEncodingAndRequestedPage() async throws {
        let url = "https://18mh.org/s/%E6%B5%8B%E8%AF%95+a%2Bb%7E*%2F/page/3"
        let source = Mh18ComicSource(transport: Mh18Transport([url: response(mh18Card)]))
        let cards = try await source.search(keyword: " 测试 a+b~*/ ", page: 3)
        XCTAssertEqual(cards.count, 1)
    }

    func testCategoryTagTakesPriorityAndAllHasNoPageSuffix() async throws {
        let transport = Mh18Transport([
            "https://18mh.org/manga-tag/hot/page/2": response(mh18Card),
            "https://18mh.org/manga-genre/hanman": response(mh18Card),
            "https://18mh.org/manga": response(mh18Card)
        ])
        let source = Mh18ComicSource(transport: transport)
        let tagged = try await source.category(filters: ["tag": "hot", "genre": "riman"], page: 2)
        let genre = try await source.category(filters: ["genre": "hanman", "tag": "all"], page: 1)
        let all = try await source.category(filters: [:], page: 1)
        XCTAssertEqual([tagged.count, genre.count, all.count], [1, 1, 1])
    }

    func testDynamicFiltersKeepTwoGroupsAndLastValueForDuplicateLabel() async throws {
        let html = "<a href='/manga-genre/kr'><button>韩漫</button></a><a href='/manga-tag/a'><button>#热门</button></a><a href='/manga-genre/hanman'><button>韩漫</button></a><a href='/manga-tag/b'><button>#校园 &amp; 日常</button></a>"
        let source = Mh18ComicSource(transport: Mh18Transport(["https://18mh.org/manga": response(html)]))
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups, [
            .init(key: "genre", label: "漫画类型", options: [.init(label: "全部", value: "all"), .init(label: "韩漫", value: "hanman")]),
            .init(key: "tag", label: "热门标签", options: [.init(label: "全部", value: "all"), .init(label: "热门", value: "a"), .init(label: "校园 & 日常", value: "b")])
        ])
    }

    func testStructuredDetailGraphArrayTypeAuthorsAndNoCatalogPrefetch() async throws {
        let html = #"<script type='application/ld+json'>{invalid}</script><script TYPE='application/ld+json'>[{"@graph":[{"@type":"BreadcrumbList"},{"@type":["Thing","ComicSeries"],"name":"目标 &amp; 漫画","image":{"url":"https://img/a.webp"},"description":"<p>描述</p>","author":[{"name":"作者甲"},"作者乙"],"genre":["剧情","日常"],"creativeWorkStatus":"連載中","hasPart":{"name":"第252話"}}]}]</script>"#
        let transport = Mh18Transport(["https://18mh.org/manga/hero": response(html)])
        let result = try await Mh18ComicSource(transport: transport).detail(comicId: "mh18:hero")
        XCTAssertEqual(result.summary.title, "目标 & 漫画")
        XCTAssertEqual(result.summary.tags, ["剧情", "日常"])
        XCTAssertEqual(result.summary.coverUrl, "https://img/a.webp")
        XCTAssertEqual(result.author, "作者甲 / 作者乙")
        XCTAssertEqual(result.description, "描述")
        XCTAssertEqual(result.status, "连载中")
        XCTAssertEqual(result.latestChapter, "第252話")
        XCTAssertEqual(result.chapters, [])
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }

    func testMetaAttributeOrderAndTagFallback() async throws {
        let html = "<meta content='目标漫画-18漫畫 -18漫畫' property='og:title'><meta content='https://img/a.webp' property='og:image'><meta content='简介 &amp; 文字' name='description'><a href='/manga-tag/a'>#恋爱</a><a href='/manga-tag/a'>#恋爱</a>"
        let result = try await Mh18ComicSource(transport: Mh18Transport(["https://18mh.org/manga/hero": response(html)])).detail(comicId: "https://18mh.org/manga/hero/1")
        XCTAssertEqual(result.summary.title, "目标漫画")
        XCTAssertEqual(result.summary.tags, ["恋爱"])
        XCTAssertEqual(result.description, "简介 & 文字")
    }

    func testCatalogLoadsAll252ChaptersInOrder() async throws {
        let directory = (0..<252).map { "<a href='/manga/hero/28-\(9821 + $0)-\($0)' data-cs='\(33999 + $0)' data-ct='第\($0 + 1)話'></a>" }.joined()
        let extra = "<a href='/manga/other/99-1-0' data-cs='1' data-ct='错误'></a><a href='/manga/hero/28-9821-0' data-cs='33999' data-ct='重复'></a>"
        let transport = Mh18Transport([
            "https://18mh.org/chapterlist/hero": response("<div id='allchapters' data-mid='28' data-host='https://API.18mh.org:443/discard?x=1'></div>"),
            "https://api.18mh.org/manga/get?mid=28&mode=all": response(directory + extra)
        ])
        let chapters = try await Mh18ComicSource(transport: transport).chapters(comicId: "mh18:hero")
        XCTAssertEqual(chapters.count, 252)
        XCTAssertEqual(chapters.first, .init(chapterId: "33999", title: "第1話", url: "https://18mh.org/manga/hero/28-9821-0", chapterSlot: 0))
        XCTAssertEqual(chapters.last, .init(chapterId: "34250", title: "第252話", url: "https://18mh.org/manga/hero/28-10072-251", chapterSlot: 251))
    }

    func testChapterAPIImagesLazyPriorityOrderDedupeAndURLIdentity() async throws {
        let transport = Mh18Transport([
            "https://18mh.org/manga/hero/1": response("<div id='chapterContent' data-ms='28' data-cs='33999' data-ct='第1話' data-host='https://18mh.org'></div>"),
            "https://18mh.org/chapter/getcontent?m=28&c=33999": response("<img src='placeholder' data-src='https://img/1.webp?a=1&amp;b=2'><img src='http://img/2.webp'><img src='https://img/1.webp?a=1&amp;b=2'><img src='/logo.png'><img src='data:image/a'><img src='javascript:alert(1)'>")
        ])
        let page = try await Mh18ComicSource(transport: transport).chapter(url: "/manga/hero/1")
        XCTAssertEqual(page, .init(chapterId: "/manga/hero/1", title: "第1話", nextPageUrl: "", imageUrls: ["https://img/1.webp?a=1&b=2", "http://img/2.webp"]))
    }

    func testUntrustedAPIHostsNeverReachTransport() async {
        for host in ["https://evil.example", "https://18mh.org.evil.example", "https://evil18mh.org", "http://api.18mh.org", "https://18mh.org:8443", "//18mh.org"] {
            let transport = Mh18Transport([
                "https://18mh.org/chapterlist/hero": response("<div id='allchapters' data-mid='28' data-host='\(host)'></div>"),
                "https://18mh.org/manga/hero/1": response("<div id='chapterContent' data-ms='28' data-cs='1' data-host='\(host)'></div>")
            ])
            let source = Mh18ComicSource(transport: transport)
            await throwsMh18(try await source.chapters(comicId: "hero")) { XCTAssertEqual($0 as? Mh18SourceError, .invalidResponse("18漫画目录参数解析失败")) }
            await throwsMh18(try await source.chapter(url: "/manga/hero/1")) { XCTAssertEqual($0 as? Mh18SourceError, .invalidResponse("18漫画章节参数解析失败")) }
            let count = await transport.requests.count
            XCTAssertEqual(count, 2)
        }
    }

    func testBrowserSessionReceivesMainAndSubdomainAPIs() async throws {
        let session = Mh18Session(pages: [
            "https://18mh.org/chapterlist/hero": "<div id='allchapters' data-mid='28' data-host='https://api.18mh.org'></div>",
            "https://api.18mh.org/manga/get?mid=28&mode=all": "<a href='/manga/hero/1' data-cs='1' data-ct='章节'></a>",
            "https://api.18mh.org/manga/hero/1": "<div id='chapterContent' data-ms='28' data-cs='1' data-host='https://api.18mh.org'></div>",
            "https://api.18mh.org/chapter/getcontent?m=28&c=1": "<img src='https://img/1.webp'>"
        ])
        let source = Mh18ComicSource(transport: Mh18Transport([:]), browserSession: session)
        let chapters = try await source.chapters(comicId: "hero")
        let chapter = try await source.chapter(url: "https://api.18mh.org/manga/hero/1")
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapter.imageUrls, ["https://img/1.webp"])
        let normal = await session.normal
        let interactive = await session.interactive
        XCTAssertEqual(normal.count, 4)
        XCTAssertEqual(interactive, [])
    }

    func testVerifyAccessOnlyUsesInteractiveAndRequiresCatalogMarker() async throws {
        let session = Mh18Session(pages: ["https://18mh.org/manga": mh18Card])
        try await Mh18ComicSource(transport: Mh18Transport([:]), browserSession: session).verifyAccess()
        let normal = await session.normal
        let interactive = await session.interactive
        XCTAssertEqual(normal, [])
        XCTAssertEqual(interactive, ["https://18mh.org/manga"])
        let bad = Mh18Session(pages: ["https://18mh.org/manga": "<main>not ready</main>"])
        await throwsMh18(try await Mh18ComicSource(browserSession: bad).verifyAccess()) { XCTAssertEqual($0 as? Mh18SourceError, .invalidResponse("18漫画 页面未就绪")) }
    }

    func testChallengeStatusHeaderOrBodyThrowsTypedVerificationWithoutInteractive() async {
        for value in [response("", status: 403, headers: ["Cf-MiTiGaTeD": "CHALLENGE"]), response("<title>Just a moment</title>")] {
            await throwsMh18(try await Mh18ComicSource(transport: Mh18Transport(["https://18mh.org/manga": value])).latest(page: 1)) { XCTAssertEqual($0 as? Mh18SourceError, .verificationRequired) }
        }
        let session = Mh18Session(pages: ["https://18mh.org/manga": "<div>Checking your browser</div>"])
        await throwsMh18(try await Mh18ComicSource(browserSession: session).latest(page: 1)) { XCTAssertEqual($0 as? Mh18SourceError, .verificationRequired) }
        let interactive = await session.interactive
        XCTAssertEqual(interactive, [])
    }

    func testOrdinaryHTTPErrorAndInvalidUTF8AreNotVerification() async {
        await throwsMh18(try await Mh18ComicSource(transport: Mh18Transport(["https://18mh.org/manga": response("Forbidden", status: 403)])).latest(page: 1)) { XCTAssertEqual($0 as? HTTPTransportError, .invalidStatusCode(403)) }
        await throwsMh18(try await Mh18ComicSource(transport: Mh18Transport(["https://18mh.org/manga": .init(data: Data([0xff]), statusCode: 200)])).latest(page: 1)) { XCTAssertEqual($0 as? Mh18SourceError, .invalidResponse("响应不是 UTF-8")) }
    }

    func testErrorShellsAndMissingCatalogOrBodyThrow() async {
        let source = Mh18ComicSource(transport: Mh18Transport([
            "https://18mh.org/manga": response("<html><title>Server error</title></html>"),
            "https://18mh.org/manga/hero": response("<html>Not found</html>"),
            "https://18mh.org/chapterlist/hero": response("<div id='allchapters' data-mid='28' data-host='https://18mh.org'></div>"),
            "https://18mh.org/manga/get?mid=28&mode=all": response("<main>Loading...</main>"),
            "https://18mh.org/manga/hero/1": response("<div id='chapterContent' data-ms='28' data-cs='1' data-host='https://18mh.org'></div>"),
            "https://18mh.org/chapter/getcontent?m=28&c=1": response("<img src='/logo.png'>")
        ]))
        await throwsMh18(try await source.latest(page: 1))
        await throwsMh18(try await source.filterGroups())
        await throwsMh18(try await source.detail(comicId: "hero"))
        await throwsMh18(try await source.chapters(comicId: "hero"))
        await throwsMh18(try await source.chapter(url: "/manga/hero/1"))
    }

    func testCancellationAfterSessionReturnCannotBecomeSuccess() async {
        let source = Mh18ComicSource(browserSession: Mh18Session(pages: ["https://18mh.org/manga": mh18Card], cancelOnReturn: true))
        let task = Task { try await source.latest(page: 1) }
        await throwsMh18(try await task.value) { XCTAssertTrue($0 is CancellationError) }
    }

    func testCancellationAfterTransportReturnCannotBecomeSuccess() async {
        let source = Mh18ComicSource(transport: Mh18Transport(["https://18mh.org/manga": response(mh18Card)], cancelOnReturn: true))
        let task = Task { try await source.latest(page: 1) }
        await throwsMh18(try await task.value) { XCTAssertTrue($0 is CancellationError) }
    }
}

private actor Mh18Transport: HTTPTransport {
    let pages: [String: HTTPResponse]
    let cancelOnReturn: Bool
    var requests: [(String, [String: String])] = []
    init(_ pages: [String: HTTPResponse], cancelOnReturn: Bool = false) { self.pages = pages; self.cancelOnReturn = cancelOnReturn }
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append((url.absoluteString, headers))
        if cancelOnReturn { withUnsafeCurrentTask { $0?.cancel() } }
        guard let value = pages[url.absoluteString] else { throw HTTPTransportError.invalidResponse }
        return value
    }
}

private actor Mh18Session: ComicBrowserSession {
    let pages: [String: String]
    let cancelOnReturn: Bool
    var normal: [String] = []
    var interactive: [String] = []
    init(pages: [String: String], cancelOnReturn: Bool = false) { self.pages = pages; self.cancelOnReturn = cancelOnReturn }
    func fetch(_ url: URL) async throws -> String {
        normal.append(url.absoluteString)
        if cancelOnReturn { withUnsafeCurrentTask { $0?.cancel() } }
        guard let value = pages[url.absoluteString] else { throw HTTPTransportError.invalidResponse }
        return value
    }
    func fetchInteractive(_ url: URL) async throws -> String {
        interactive.append(url.absoluteString)
        guard let value = pages[url.absoluteString] else { throw HTTPTransportError.invalidResponse }
        return value
    }
}

private func response(_ html: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
    .init(data: Data(html.utf8), statusCode: status, headers: headers)
}

private func throwsMh18<T>(_ expression: @autoclosure () async throws -> T, _ check: (Error) -> Void = { XCTAssertNotNil($0 as? Mh18SourceError) }, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) } catch { check(error) }
}
