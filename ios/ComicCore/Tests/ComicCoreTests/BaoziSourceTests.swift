import XCTest
@testable import ComicCore

final class BaoziSourceTests: XCTestCase {
    func testIdentityAndFiltersMatchAndroidSource() async throws {
        let source = BaoziComicSource(transport: BaoziStubTransport(responses: [:]))

        XCTAssertEqual(source.id, "baozimh")
        XCTAssertEqual(source.name, "包子漫画")
        XCTAssertEqual(source.referer, "https://cn.dzmanga.com/")
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups, [
            SourceFilterGroup(key: "region", label: "地区", options: [
                .init(label: "全部", value: "all"), .init(label: "国漫", value: "cn"),
                .init(label: "日本", value: "jp"), .init(label: "韩国", value: "kr"),
                .init(label: "欧美", value: "en")
            ]),
            SourceFilterGroup(key: "state", label: "状态", options: [
                .init(label: "全部", value: "all"), .init(label: "连载中", value: "serial"),
                .init(label: "已完结", value: "pub")
            ]),
            SourceFilterGroup(key: "type", label: "题材", options: [
                .init(label: "全部", value: "all"), .init(label: "恋爱", value: "lianai"),
                .init(label: "纯爱", value: "chunai"), .init(label: "古风", value: "gufeng"),
                .init(label: "异能", value: "yineng"), .init(label: "悬疑", value: "xuanyi"),
                .init(label: "剧情", value: "juqing"), .init(label: "科幻", value: "kehuan"),
                .init(label: "奇幻", value: "qihuan"), .init(label: "玄幻", value: "xuanhuan"),
                .init(label: "穿越", value: "chuanyue"), .init(label: "冒险", value: "mouxian"),
                .init(label: "推理", value: "tuili"), .init(label: "武侠", value: "wuxia"),
                .init(label: "格斗", value: "gedou"), .init(label: "战争", value: "zhanzheng"),
                .init(label: "热血", value: "rexie"), .init(label: "搞笑", value: "gaoxiao"),
                .init(label: "大女主", value: "danuzhu"), .init(label: "都市", value: "dushi"),
                .init(label: "总裁", value: "zongcai"), .init(label: "后宫", value: "hougong"),
                .init(label: "日常", value: "richang"), .init(label: "韩漫", value: "hanman"),
                .init(label: "少年", value: "shaonian"), .init(label: "其它", value: "qita")
            ]),
            SourceFilterGroup(key: "filter", label: "字母", options: [
                .init(label: "全部", value: "*"), .init(label: "ABCD", value: "ABCD"),
                .init(label: "EFGH", value: "EFGH"), .init(label: "IJKL", value: "IJKL"),
                .init(label: "MNOP", value: "MNOP"), .init(label: "QRST", value: "QRST"),
                .init(label: "UVW", value: "UVW"), .init(label: "XYZ", value: "XYZ"),
                .init(label: "0-9", value: "0-9")
            ])
        ])
    }

    func testLatestAndSearchUseAndroidRoutesHeadersAndCardMapping() async throws {
        let html = """
        <html><div class="comics-list">
          <div class="comics-card"><a href="/comic/hero-one" title=" Hero &amp; One ">
            <img src="https://img.example/one.webp?x=1&amp;y=2">
            <small class="tags text-truncate">热血 / 最新更新 / 冒险&nbsp;故事</small>
          </a></div>
        </div></html>
        """
        let transport = BaoziStubTransport(responses: [
            "https://cn.dzmanga.com/list/new/2": baoziResponse(html),
            "https://cn.dzmanga.com/search?q=%E6%AD%A6+%26+love": baoziResponse(html)
        ])
        let source = BaoziComicSource(transport: transport)

        let latest = try await source.latest(page: 2)
        let search = try await source.search(keyword: "武 & love", page: 3)

        let expected = ComicSummary(
            sourceId: "baozimh", comicId: "hero-one", title: "Hero & One",
            coverUrl: "https://img.example/one.webp?x=1", subtitle: "热血 / 最新更新 / 冒险 故事",
            tags: ["热血", "冒险", "故事"]
        )
        XCTAssertEqual(latest, [expected])
        XCTAssertEqual(search, [expected])
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url), [
            "https://cn.dzmanga.com/list/new/2",
            "https://cn.dzmanga.com/search?q=%E6%AD%A6+%26+love"
        ])
        XCTAssertTrue(requests.allSatisfy {
            $0.headers["Referer"] == "https://cn.dzmanga.com/" &&
            $0.headers["User-Agent"] == "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        })
    }

    func testCategoryUsesHTMLFirstPageAndAPIForLaterPages() async throws {
        let html = """
        <html><div class="comics-list"><div class="comics-card">
          <a href="/comic/first" title="First"><img src="//img.example/first.jpg">
          <small class="tags text-truncate">恋爱</small></a>
        </div></div></html>
        """
        let api = """
        {"items":[{"comic_id":"second","name":"Second","author":"Author &amp; Co", "topic_img":"second.jpg","type_names":["奇幻","奇幻"," 热血 "]}]}
        """
        let firstURL = "https://cn.dzmanga.com/classify?type=rexie&region=jp&state=serial&filter=ABCD"
        let secondURL = "https://cn.dzmanga.com/api/bzmhq/amp_comic_list?limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.dzmanga.com&type=qihuan&region=kr&state=pub&filter=XYZ&page=3"
        let transport = BaoziStubTransport(responses: [
            firstURL: baoziResponse(html), secondURL: baoziResponse(api)
        ])
        let source = BaoziComicSource(transport: transport)

        let first = try await source.category(filters: ["type": "rexie", "region": "jp", "state": "serial", "filter": "ABCD"], page: 1)
        let second = try await source.category(filters: ["type": "qihuan", "region": "kr", "state": "pub", "filter": "XYZ"], page: 3)

        XCTAssertEqual(first, [.init(sourceId: "baozimh", comicId: "first", title: "First", coverUrl: "//img.example/first.jpg", subtitle: "恋爱", tags: ["恋爱"])])
        XCTAssertEqual(second, [.init(sourceId: "baozimh", comicId: "second", title: "Second", coverUrl: "https://static-tw.baozimh.com/cover/second.jpg?w=285&h=375&q=100", subtitle: "Author & Co", tags: ["奇幻", "热血"])])
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url), [firstURL, secondURL])
    }

    func testDetailMapsNovelMetadataAndDropsInternalTags() async throws {
        let html = """
        <html><head>
          <meta property="og:novel:book_name" content=" Hero &amp; One ">
          <meta name="og:novel:author" content="Alice &amp; Bob">
          <meta data-hid="og:novel:status" content="连载中">
          <meta property="og:description" content="Line&nbsp; one">
          <meta property="og:novel:latest_chapter_name" content="第 9 话">
          <meta property="og:image" content="https://img.example/cover.jpg?x=1&amp;y=2">
          <meta property="og:novel:category" content="奇幻, types.hidden, 热血">
        </head></html>
        """
        let source = BaoziComicSource(transport: BaoziStubTransport(responses: [
            "https://cn.dzmanga.com/comic/hero-one": baoziResponse(html)
        ]))

        let detail = try await source.detail(comicId: "hero-one")

        XCTAssertEqual(detail, ComicDetail(
            summary: .init(sourceId: "baozimh", comicId: "hero-one", title: "Hero & One", coverUrl: "https://img.example/cover.jpg?x=1", subtitle: "第 9 话", tags: ["奇幻", "热血"]),
            author: "Alice & Bob", status: "连载中", description: "Line one", latestChapter: "第 9 话", chapters: []
        ))
    }

    func testChaptersDecodeLegacyHostAndSortBySlots() async throws {
        let html = """
        <html><div class="comics-chapters">
          <a href="https://www.baozimh.com/comic/chapter/hero/0_2.html?page_direct=1&amp;section_slot=2&amp;chapter_slot=1" class="comics-chapters__item"><span> Second &amp; More </span></a>
          <a href="/comic/chapter/hero/0_1.html?page_direct=1&amp;section_slot=1&amp;chapter_slot=9" class="comics-chapters__item"><span><b>First</b></span></a>
        </div></html>
        """
        let source = BaoziComicSource(transport: BaoziStubTransport(responses: [
            "https://cn.dzmanga.com/comic/hero": baoziResponse(html)
        ]))

        let chapters = try await source.chapters(comicId: "hero")

        XCTAssertEqual(chapters, [
            Chapter(chapterId: "1_9", title: "First", url: "https://cn.dzmanga.com/comic/chapter/hero/0_1.html?page_direct=1&section_slot=1&chapter_slot=9", sectionSlot: 1, chapterSlot: 9),
            Chapter(chapterId: "2_1", title: "Second & More", url: "https://cn.dzmanga.com/comic/chapter/hero/0_2.html?page_direct=1&section_slot=2&chapter_slot=1", sectionSlot: 2, chapterSlot: 1)
        ])
    }

    func testChapterExtractsAmpImagesDeduplicatesAndFindsNextPage() async throws {
        let html = """
        <html><head><title> Hero &amp; One - 2 </title></head><body><div class="comic-contain">
          <amp-img src="https://img.example/scomic/1.webp?x=1&amp;y=2"></amp-img>
          <amp-img data-src="https://img.example/scomic/2.JPG"></amp-img>
          <amp-img src="https://img.example/cover/ignored.webp"></amp-img>
          <amp-img src="https://img.example/scomic/1.webp?x=1&amp;y=2"></amp-img>
        </div><div class="next_chapter"><a href="https://www.twmanga.com/comic/chapter/hero/0_2.html?page_direct=2&amp;x=1">Next</a></div></body></html>
        """
        let chapterURL = "https://cn.dzmanga.com/comic/chapter/hero/0_2.html?page_direct=1"
        let source = BaoziComicSource(transport: BaoziStubTransport(responses: [
            chapterURL: baoziResponse(html)
        ]))

        let page = try await source.chapter(url: chapterURL)

        XCTAssertEqual(page, ChapterPage(
            chapterId: chapterURL, title: "Hero & One - 2",
            nextPageUrl: "https://cn.dzmanga.com/comic/chapter/hero/0_2.html?page_direct=2&x=1",
            imageUrls: ["https://img.example/scomic/1.webp?x=1", "https://img.example/scomic/2.JPG"]
        ))
    }

    func testExplicitEmptyCollectionsAreAccepted() async throws {
        let transport = BaoziStubTransport(responses: [
            "https://cn.dzmanga.com/list/new": baoziResponse("<html><div class=\"comics-list\"></div></html>"),
            "https://cn.dzmanga.com/comic/empty": baoziResponse("<html><div class=\"comics-chapters\"></div></html>"),
            "https://cn.dzmanga.com/comic/chapter/empty/0_0.html?page_direct=1": baoziResponse("<html><title>Empty</title><div class=\"comic-contain\"></div></html>"),
            "https://cn.dzmanga.com/api/bzmhq/amp_comic_list?limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.dzmanga.com&type=all&region=all&state=all&filter=*&page=2": baoziResponse("{\"items\":[]}")
        ])
        let source = BaoziComicSource(transport: transport)

        let latest = try await source.latest(page: 1)
        let chapters = try await source.chapters(comicId: "empty")
        let chapter = try await source.chapter(url: "https://cn.dzmanga.com/comic/chapter/empty/0_0.html?page_direct=1")
        let category = try await source.category(filters: [:], page: 2)
        XCTAssertEqual(latest, [])
        XCTAssertEqual(chapters, [])
        XCTAssertEqual(chapter.imageUrls, [])
        XCTAssertEqual(category, [])
    }

    func testMalformedResponsesThrowInsteadOfLookingEmpty() async {
        let operations: [(String, BaoziComicSource, (BaoziComicSource) async throws -> Void)] = [
            ("cards", BaoziComicSource(transport: BaoziStubTransport(responses: ["https://cn.dzmanga.com/list/new": baoziResponse("not html")])), { source in _ = try await source.latest(page: 1) }),
            ("chapters", BaoziComicSource(transport: BaoziStubTransport(responses: ["https://cn.dzmanga.com/comic/bad": baoziResponse("not html")])), { source in _ = try await source.chapters(comicId: "bad") }),
            ("images", BaoziComicSource(transport: BaoziStubTransport(responses: ["https://cn.dzmanga.com/chapter/bad": baoziResponse("not html")])), { source in _ = try await source.chapter(url: "/chapter/bad") }),
            ("api JSON", BaoziComicSource(transport: BaoziStubTransport(responses: ["https://cn.dzmanga.com/api/bzmhq/amp_comic_list?limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.dzmanga.com&type=all&region=all&state=all&filter=*&page=2": baoziResponse("{\"data\":[]}")])), { source in _ = try await source.category(filters: [:], page: 2) })
        ]

        for (name, source, operation) in operations {
            await XCTAssertBaoziThrows(try await operation(source), name: name) { error in
                XCTAssertNotNil(error as? BaoziSourceError)
            }
        }
    }

    func testHTTPUTF8TransportAndCancellationErrorsPropagate() async {
        let status = BaoziComicSource(transport: BaoziStubTransport(responses: [
            "https://cn.dzmanga.com/list/new": baoziResponse("error", statusCode: 503)
        ]))
        await XCTAssertBaoziThrows(try await status.latest(page: 1)) { error in
            XCTAssertEqual(error as? HTTPTransportError, .invalidStatusCode(503))
        }

        let utf8 = BaoziComicSource(transport: BaoziStubTransport(responses: [
            "https://cn.dzmanga.com/list/new": HTTPResponse(data: Data([0xff]), statusCode: 200)
        ]))
        await XCTAssertBaoziThrows(try await utf8.latest(page: 1)) { error in
            XCTAssertEqual(error as? BaoziSourceError, .invalidResponse("响应不是 UTF-8"))
        }

        let cancelled = BaoziComicSource(transport: BaoziCancellingTransport())
        await XCTAssertBaoziThrows(try await cancelled.latest(page: 1)) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
}

private struct BaoziCapturedRequest: Sendable {
    let url: String
    let headers: [String: String]
}

private enum BaoziStubError: Error {
    case missingResponse(String)
}

private actor BaoziStubTransport: HTTPTransport {
    private let responses: [String: HTTPResponse]
    private var captured: [BaoziCapturedRequest] = []

    init(responses: [String: HTTPResponse]) {
        self.responses = responses
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        captured.append(.init(url: url.absoluteString, headers: headers))
        guard let response = responses[url.absoluteString] else { throw BaoziStubError.missingResponse(url.absoluteString) }
        return response
    }

    func requests() -> [BaoziCapturedRequest] { captured }
}

private struct BaoziCancellingTransport: HTTPTransport {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        throw CancellationError()
    }
}

private func baoziResponse(_ body: String, statusCode: Int = 200) -> HTTPResponse {
    HTTPResponse(data: Data(body.utf8), statusCode: statusCode)
}

private func XCTAssertBaoziThrows<T>(
    _ expression: @autoclosure () async throws -> T,
    name: String = "",
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw \(name)", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
