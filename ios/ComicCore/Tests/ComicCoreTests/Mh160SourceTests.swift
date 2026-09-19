import XCTest
@testable import ComicCore

final class Mh160SourceTests: XCTestCase {
    func testIdentityLatestSearchAndCardsMatchAndroidContracts() async throws {
        let html = """
        <html><body><ul class="mh-search-list clearfix">
          <li><div class="mh-worksbox"><a href="/kanmanhua/4974/?from=list">
            <img data-original="//img.test/cover.jpg@!180x240@!180x240" alt="ignored">
          </a></div><div class="mh-works-info">
            <h4><a title="ignored">Wait&hellip; &mdash; &#x96CF;&#34562; &lt;b&gt;safe&lt;/b&gt;</a></h4>
            <p class="mh-works-author">状态：连载中&nbsp;</p>
            <p class="mh-works-tags"><a>科幻</a><a>科幻</a><a>冒险</a></p>
          </div></li>
        </ul><div class="recommend"><a href="/kanmanhua/999/"><img src="recommend.jpg"></a></div></body></html>
        """
        let transport = Mh160StubTransport(responses: [
            "https://www.mh160mh.com/kanmanhua/all/2.html": mh160Response(html),
            "https://www.mh160mh.com/statics/searchelxt1e1.aspx?key=%E6%AD%A6+%26+love&page=3": mh160Response(html)
        ])
        let source = Mh160ComicSource(transport: transport)

        XCTAssertEqual(source.id, "mh160")
        XCTAssertEqual(source.name, "漫画160")
        XCTAssertEqual(source.referer, "https://www.mh160mh.com/")
        let expected = ComicSummary(
            sourceId: "mh160", comicId: "mh160:4974", title: "Wait… — 雏蜂 safe",
            coverUrl: "https://img.test/cover.jpg", subtitle: "连载中", tags: ["科幻", "冒险"]
        )
        let latest = try await source.latest(page: 2)
        let search = try await source.search(keyword: " 武 & love ", page: 3)
        XCTAssertEqual(latest, [expected])
        XCTAssertEqual(search, [expected])
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url), [
            "https://www.mh160mh.com/kanmanhua/all/2.html",
            "https://www.mh160mh.com/statics/searchelxt1e1.aspx?key=%E6%AD%A6+%26+love&page=3"
        ])
        XCTAssertTrue(requests.allSatisfy {
            $0.headers["Referer"] == "https://www.mh160mh.com/" &&
            $0.headers["User-Agent"] == "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        })
    }

    func testFilterGroupsPreserveDocumentOrderAndCategoryUsesFirstSelectedPriority() async throws {
        let filters = """
        <html><body>
          <div class="mh-tags"><h4 class="mh-tags-lx">进度</h4><div class="mh-tags-box">
            <a href="/kanmanhua/all/">全部</a><a href="/kanmanhua/lianzai/?x=1">连载</a><a href="/kanmanhua/wanjie/">完结</a></div></div>
          <div class="mh-tags"><h4 class="mh-tags-lx">题材</h4><div class="mh-tags-box">
            <a href="/kanmanhua/all/">全部</a><a href="/kanmanhua/rexue/">热血</a></div></div>
          <div class="mh-tags"><h4 class="mh-tags-lx">字母</h4><div class="mh-tags-box">
            <a href="/kanmanhua/all/">全部</a><a href="/kanmanhua/lettera/">A</a></div></div>
        </body></html>
        """
        let emptyList = "<html><body><ul class='mh-search-list'></ul></body></html>"
        let transport = Mh160StubTransport(responses: [
            "https://www.mh160mh.com/kanmanhua/all/": mh160Response(filters),
            "https://www.mh160mh.com/kanmanhua/wanjie/2.html": mh160Response(emptyList)
        ])
        let source = Mh160ComicSource(transport: transport)

        let groups = try await source.filterGroups()
        XCTAssertEqual(groups, [
            .init(key: "state", label: "状态", options: [
                .init(label: "全部", value: "all"), .init(label: "连载", value: "/lianzai"),
                .init(label: "完结", value: "/wanjie")
            ]),
            .init(key: "subject", label: "题材", options: [
                .init(label: "全部", value: "all"), .init(label: "热血", value: "/rexue")
            ]),
            .init(key: "letter", label: "字母", options: [
                .init(label: "全部", value: "all"), .init(label: "A", value: "/lettera")
            ])
        ])
        let category = try await source.category(filters: ["letter": "/lettera", "subject": "/rexue", "state": "/wanjie"], page: 2)
        XCTAssertEqual(category, [])
        let requests = await transport.requests()
        XCTAssertEqual(requests.last?.url, "https://www.mh160mh.com/kanmanhua/wanjie/2.html")
    }

    func testDetailNormalizesLegacyIDAndIncludesOldestFirstScopedCatalog() async throws {
        let html = """
        <html><body><div class="mh-date-info fl"><div class="mh-date-info-name"><h4><a>雏蜂&amp;续</a></h4></div>
          <p class="works-info-tc"><span>作者：<em>出云&amp;社</em></span></p>
          <p class="works-info-tc"><span>状态：<em>连载中</em></span></p>
          <div class="work-introd"><div id="workint"><p>简介&nbsp;内容</p></div></div></div>
          <div class="mh-cover"><img src="/covers/4974.jpg@!180x240@!180x240"></div>
          <div class="mh-label"><a>科幻</a><a>冒险</a></div>
          <div class="cy_plist"><ul>
            <li><a href="https://www.mh160mh.com/kanmanhua/4974/103.html?x=1"><p>第3话</p></a></li>
            <li><a href="/kanmanhua/4974/102.html"><p>第2话</p></a></li>
            <li><a href="/kanmanhua/4974/102.html"><p>重复</p></a></li>
            <li><a href="/kanmanhua/4974/101.html"><p>第1话</p></a></li>
          </ul></div><div class="recommend"><a href="/kanmanhua/999/1.html">推荐章节</a></div>
        </body></html>
        """
        let transport = Mh160StubTransport(responses: [
            "https://www.mh160mh.com/kanmanhua/4974/": mh160Response(html)
        ])
        let source = Mh160ComicSource(transport: transport)

        let detail = try await source.detail(comicId: "mh160:https://legacy.example/kanmanhua/4974.html?old=1")

        XCTAssertEqual(detail.summary, .init(
            sourceId: "mh160", comicId: "mh160:4974", title: "雏蜂&续",
            coverUrl: "https://www.mh160mh.com/covers/4974.jpg", subtitle: "出云&社", tags: ["科幻", "冒险"]
        ))
        XCTAssertEqual(detail.author, "出云&社")
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.description, "简介 内容")
        XCTAssertEqual(detail.chapters, [
            .init(chapterId: "101", title: "第1话", url: "https://www.mh160mh.com/kanmanhua/4974/101.html", chapterSlot: 2),
            .init(chapterId: "102", title: "第2话", url: "https://www.mh160mh.com/kanmanhua/4974/102.html", chapterSlot: 1),
            .init(chapterId: "103", title: "第3话", url: "https://www.mh160mh.com/kanmanhua/4974/103.html?x=1", chapterSlot: 0)
        ])
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url), ["https://www.mh160mh.com/kanmanhua/4974/"])
    }

    func testChapterDecodesPayloadFiltersNoiseDeduplicatesAndSwitchesImageHosts() async throws {
        let payload = [
            "/mh160tuku/c/comic/0001.jpg", "/recommend/banner.jpg",
            "http://auto.mangafiles.com:88/mh160tuku/c/comic/0002.jpg",
            "/mh160tuku/c/comic/0001.jpg", "/tuijian/skip.jpg"
        ].joined(separator: "$qingtiandy$")
        let encoded = Data(payload.utf8).base64EncodedString()
        let modernURL = "https://www.mh160mh.com/kanmanhua/4974/2055611.html?from=reader"
        let legacyURL = "https://www.mh160mh.com/kanmanhua/4974/20380.html"
        let transport = Mh160StubTransport(responses: [
            modernURL: mh160Response("<html><title>第 560 话&amp;终</title><script>var qTcms_S_p_id='2055611'; var qTcms_S_m_murl_e='\(encoded)';</script></html>"),
            legacyURL: mh160Response("<html><title>旧话</title><script>var qTcms_S_p_id='20380'; var qTcms_S_m_murl_e='\(encoded)';</script></html>")
        ])
        let source = Mh160ComicSource(transport: transport)

        let modern = try await source.chapter(url: modernURL)
        let legacy = try await source.chapter(url: legacyURL)
        XCTAssertEqual(modern, .init(
            chapterId: "2055611", title: "第 560 话&终", nextPageUrl: "", imageUrls: [
                "https://xwdf.tgmhfc.uk/mh160tuku/c/comic/0001.jpg",
                "https://xwdf.tgmhfc.uk/mh160tuku/c/comic/0002.jpg"
            ]
        ))
        XCTAssertEqual(legacy.imageUrls, [
            "https://mhpic6.tgmhfc.uk/mh160tuku/c/comic/0001.jpg",
            "https://mhpic6.tgmhfc.uk/mh160tuku/c/comic/0002.jpg"
        ])
    }

    func testExplicitEmptyBusinessContainersAreAccepted() async throws {
        let transport = Mh160StubTransport(responses: [
            "https://www.mh160mh.com/kanmanhua/all/": mh160Response("<html><ul class='mh-search-list'></ul></html>"),
            "https://www.mh160mh.com/kanmanhua/empty/": mh160Response("<html><div class='cy_plist'><ul></ul></div></html>"),
            "https://www.mh160mh.com/kanmanhua/empty/0.html": mh160Response("<html><title>Empty</title><script>var qTcms_S_m_murl_e='';</script></html>")
        ])
        let source = Mh160ComicSource(transport: transport)

        let latest = try await source.latest(page: 1)
        let chapters = try await source.chapters(comicId: "empty")
        let chapter = try await source.chapter(url: "/kanmanhua/empty/0.html")
        XCTAssertEqual(latest, [])
        XCTAssertEqual(chapters, [])
        XCTAssertEqual(chapter.imageUrls, [])
    }

    func testMalformedHTMLAndErrorShellsThrowInsteadOfLookingEmpty() async {
        let shell = "<html><head><title>Sign in</title></head><body><h1>Rate limited</h1></body></html>"
        let operations: [(Mh160ComicSource, (Mh160ComicSource) async throws -> Void)] = [
            (Mh160ComicSource(transport: Mh160StubTransport(responses: ["https://www.mh160mh.com/kanmanhua/all/": mh160Response(shell)])), { _ = try await $0.latest(page: 1) }),
            (Mh160ComicSource(transport: Mh160StubTransport(responses: ["https://www.mh160mh.com/kanmanhua/bad/": mh160Response(shell)])), { _ = try await $0.chapters(comicId: "bad") }),
            (Mh160ComicSource(transport: Mh160StubTransport(responses: ["https://www.mh160mh.com/kanmanhua/bad/1.html": mh160Response(shell)])), { _ = try await $0.chapter(url: "/kanmanhua/bad/1.html") }),
            (Mh160ComicSource(transport: Mh160StubTransport(responses: ["https://www.mh160mh.com/kanmanhua/all/": mh160Response("not html")])), { _ = try await $0.filterGroups() })
        ]

        for (source, operation) in operations {
            await XCTAssertMh160Throws(try await operation(source)) { error in
                XCTAssertNotNil(error as? Mh160SourceError)
            }
        }
    }

    func testHTTPUTF8AndCancellationErrorsPropagate() async {
        let status = Mh160ComicSource(transport: Mh160StubTransport(responses: [
            "https://www.mh160mh.com/kanmanhua/all/": mh160Response("error", statusCode: 503)
        ]))
        await XCTAssertMh160Throws(try await status.latest(page: 1)) {
            XCTAssertEqual($0 as? HTTPTransportError, .invalidStatusCode(503))
        }

        let utf8 = Mh160ComicSource(transport: Mh160StubTransport(responses: [
            "https://www.mh160mh.com/kanmanhua/all/": .init(data: Data([0xff]), statusCode: 200)
        ]))
        await XCTAssertMh160Throws(try await utf8.latest(page: 1)) {
            XCTAssertEqual($0 as? Mh160SourceError, .invalidResponse("响应不是 UTF-8"))
        }

        let cancelled = Mh160ComicSource(transport: Mh160CancellingTransport())
        await XCTAssertMh160Throws(try await cancelled.latest(page: 1)) {
            XCTAssertTrue($0 is CancellationError)
        }
    }
}

private struct Mh160CapturedRequest: Sendable {
    let url: String
    let headers: [String: String]
}

private enum Mh160StubError: Error {
    case missingResponse(String)
}

private actor Mh160StubTransport: HTTPTransport {
    private let responses: [String: HTTPResponse]
    private var captured: [Mh160CapturedRequest] = []

    init(responses: [String: HTTPResponse]) {
        self.responses = responses
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        captured.append(.init(url: url.absoluteString, headers: headers))
        guard let response = responses[url.absoluteString] else { throw Mh160StubError.missingResponse(url.absoluteString) }
        return response
    }

    func requests() -> [Mh160CapturedRequest] { captured }
}

private struct Mh160CancellingTransport: HTTPTransport {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        throw CancellationError()
    }
}

private func mh160Response(_ body: String, statusCode: Int = 200) -> HTTPResponse {
    HTTPResponse(data: Data(body.utf8), statusCode: statusCode)
}

private func XCTAssertMh160Throws<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
