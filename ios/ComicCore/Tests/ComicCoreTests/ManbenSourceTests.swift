import XCTest
@testable import ComicCore

final class ManbenSourceTests: XCTestCase {
    func testImportedCategoryRouteAndSortReachLatestAndSelectedFilters() async throws {
        let suite = "ManbenSourceTests.config." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["manben"])
        _ = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"manben","baseUrl":"https://fixture.invalid","referer":"https://fixture.invalid/ref/","routes":{"category":"/configured-list"},"filters":{"sort.latest":"7","state.all":"8"}}]}"#)
        let transport = ManbenFixtureTransport(["[]", "[]"])
        let source = ManbenComicSource(config: try XCTUnwrap(store.config(for: "manben")), transport: transport)
        _ = try await source.latest(page: 2)
        _ = try await source.category(filters: ["state": "2", "tag": "31", "region": "36", "letter": "B"], page: 3)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url), Array(repeating: "https://fixture.invalid/configured-list", count: 2))
        XCTAssertEqual(requests.map(\.method), ["POST", "POST"])
        XCTAssertEqual(requests[0].body, "t=2&pageindex=2&sc=1&tsort=7&tagid=0&tst=8&tarea=0&tgroup=0&tnm=")
        XCTAssertEqual(requests[1].body, "t=2&pageindex=3&sc=1&tsort=7&tagid=31&tst=2&tarea=36&tgroup=0&tnm=B")
        XCTAssertEqual(requests.map { $0.headers["Referer"] }, Array(repeating: "https://fixture.invalid/ref/", count: 2))
    }

    func testSelectedAllValuesResetImportedCategoryDefaultsLikeAndroid() async throws {
        let config = SourceConfigItem(id: "manben", name: "漫本", baseUrl: "https://fixture.invalid",
                                     routes: ["category": "/list"],
                                     filters: ["sort.latest": "7", "state.all": "8", "category.全部": "tagid:37"])
        let transport = ManbenFixtureTransport(["[]"])
        let source = ManbenComicSource(config: config, transport: transport)
        _ = try await source.category(filters: [:], page: 0)
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url, "https://fixture.invalid/list")
        XCTAssertEqual(requests[0].body, "t=2&pageindex=1&sc=1&tsort=7&tagid=0&tst=0&tarea=0&tgroup=0&tnm=")
    }

    func testLegacyCategoryNamesUseConfiguredAndroidFieldMappings() async throws {
        let config = SourceConfigItem(id: "manben", name: "漫本", baseUrl: "https://fixture.invalid",
                                     routes: ["category": "/list"],
                                     filters: ["category.地区·日韩": "tarea:36", "state.serial": "6", "sort.latest": "7"])
        let transport = ManbenFixtureTransport(["[]"])
        let source = ManbenComicSource(config: config, transport: transport)
        _ = try await source.category(region: "地区·日韩", state: "serial", page: 4)
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url, "https://fixture.invalid/list")
        XCTAssertEqual(requests[0].body, "t=2&pageindex=4&sc=1&tsort=7&tagid=0&tst=6&tarea=36&tgroup=0&tnm=")
    }

    func testCategoryPostsAndroidFieldsAndParsesMetadata() async throws {
        let transport = ManbenFixtureTransport(["""
        [{"Url":"/mh-stars/","Title":"星&amp;海","BigPic":"//img.test/c.jpg","Author":["作者"],"LastPartShowName":"第2话","TagList":["热血","热血","奇幻"]},{"Url":"/mh-stars/","Title":"重复"}]
        """, "[]"])
        let source = ManbenComicSource(transport: transport)
        let items = try await source.latest(page: 2)
        XCTAssertEqual(items, [.init(sourceId: "manben", comicId: "manben:stars", title: "星&海", coverUrl: "https://img.test/c.jpg", subtitle: "作者", tags: ["热血", "奇幻"])])
        _ = try await source.category(filters: ["state":"2", "tag":"31", "audience":"1", "region":"3", "letter":"A &~*"], page: 0)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.method), ["POST", "POST"])
        XCTAssertEqual(requests[0].url, "https://www.manben.com/mh-list/pagerdata.ashx")
        XCTAssertEqual(requests[0].body, "t=2&pageindex=2&sc=1&tsort=2&tagid=0&tst=0&tarea=0&tgroup=0&tnm=")
        XCTAssertEqual(requests[1].body, "t=2&pageindex=1&sc=1&tsort=2&tagid=31&tst=2&tarea=3&tgroup=1&tnm=A+%26%7E*")
        XCTAssertEqual(requests[0].headers["Content-Type"], "application/x-www-form-urlencoded; charset=UTF-8")
    }

    func testSearchPaginationAndFiltersFollowAndroidValues() async throws {
        let transport = ManbenFixtureTransport(["""
        <div class="item"><a href="/mh-stars/"><img class="cover" data-original="/c.jpg"></a><div class="title"><a>星&amp;海</a></div><p class="tip">新章</p></div><div class="pager"></div>
        """, """
        <ul><li><div class="title">地区</div><div class="list"><a onclick="tagClick(4, 'all')">全部</a><a onclick="tagClick(4, '2')">日本</a></div></li><li><div class="title">字母</div><div class="list"><a onclick="tagClick(5, 'A')">A</a></div></li></ul>
        """])
        let source = ManbenComicSource(transport: transport)
        let items = try await source.search(keyword: " 星 &~* ", page: 3)
        XCTAssertEqual(items.first?.comicId, "manben:stars")
        XCTAssertEqual(items.first?.title, "星&海")
        XCTAssertEqual(items.first?.coverUrl, "https://www.manben.com/c.jpg")
        let filters = try await source.filterGroups()
        XCTAssertEqual(filters, [.init(key: "region", label: "地区", options: [.init(label: "全部", value: "all"), .init(label: "日本", value: "2")]), .init(key: "letter", label: "字母", options: [.init(label: "A", value: "A")])])
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url, "https://www.manben.com/search?page=3&title=%E6%98%9F+%26%7E*&language=1")
    }

    func testSearchRejectsInvalidItemsAndAcceptsExplicitEmptyResult() async throws {
        let invalid = ManbenComicSource(transport: ManbenFixtureTransport([
            #"<div class="item"><p>请输入验证码后继续访问</p></div>"#
        ]))
        do {
            _ = try await invalid.search(keyword: "漫画", page: 1)
            XCTFail("无有效漫画的 item 不能冒充搜索无结果")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("搜索列表解析失败"))
        }

        let notFound = ManbenComicSource(transport: ManbenFixtureTransport([
            #"<html><h1>没有找到您访问的页面</h1><a href="/hot">热门漫画</a></html>"#
        ]))
        do {
            _ = try await notFound.search(keyword: "漫画", page: 1)
            XCTFail("404 页面不能冒充搜索无结果")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("搜索列表解析失败"))
        }

        let empty = ManbenComicSource(transport: ManbenFixtureTransport([
            #"<div class="search-empty">没有找到相关漫画</div>"#
        ]))
        let items = try await empty.search(keyword: "不存在", page: 1)
        XCTAssertEqual(items, [])
    }

    func testDetailStripsNestedScoreAndCatalogKeepsGroupsSorted() async throws {
        let html = """
        <div class="comicInfo"><p class="title"><span class="grading"><span>9.2</span>分</span> 星&amp;海</p><div class="cover"><img data-src="/c.jpg"></div><a href="{{ a > b }}" class="user avatar"><b>作者</b></a><p>状 态：连载中</p><p>类 别：热血/奇幻</p><p class="content">介绍<br>第二行</p><a href="/m20/" class="op">第20话</a></div>
        <div id="chapterlistload"><div class="list"><a href="/m20/">第20话</a><a href="/m2/">第2话</a><a href="/m2/">重复</a></div><div class="list"><a href="/m1/">番外</a></div></div><a href="/m999/">推荐</a>
        """
        let source = ManbenComicSource(transport: ManbenFixtureTransport([html, html]))
        let detail = try await source.detail(comicId: "manben:https://old.test/mh-stars/")
        XCTAssertEqual(detail.summary.title, "星&海")
        XCTAssertEqual(detail.author, "作者")
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.description, "介绍 第二行")
        XCTAssertEqual(detail.latestChapter, "第20话")
        XCTAssertTrue(detail.chapters.isEmpty)
        let chapters = try await source.chapters(comicId: "manben:stars")
        XCTAssertEqual(chapters.map(\.chapterId), ["2", "20", "1"])
        XCTAssertEqual(chapters.map(\.sectionSlot), [0, 0, 1])
        XCTAssertEqual(chapters.map(\.chapterSlot), [0, 1, 2])
    }

    func testChapterAccumulatesSpreadPagesUntilExplicitEnd() async throws {
        let transport = ManbenFixtureTransport([
            "<title>第2话 - 漫本</title><div class=\"myview\"></div>",
            "var chapterimage={\"ImagePix\":\"https://img.test/\",\"Images\":[\"1.jpg\",\"https://other.test/ad.jpg\"],\"IsEnd\":false};",
            "var chapterimage={\"ImagePix\":\"https://img.test/\",\"Images\":[\"1.jpg\",\"2.jpg\"],\"IsEnd\":true};"
        ])
        let page = try await ManbenComicSource(transport: transport).chapter(url: "/m2/")
        XCTAssertEqual(page.title, "第2话")
        XCTAssertEqual(page.imageUrls, ["https://img.test/1.jpg", "https://img.test/2.jpg"])
        XCTAssertEqual(page.nextPageUrl, "")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url), ["https://www.manben.com/m2/", "https://www.manben.com/imageshow.ashx?cid=2&page=1&showtype=1&ispre=0", "https://www.manben.com/imageshow.ashx?cid=2&page=2&showtype=1&ispre=0"])
        XCTAssertEqual(requests[1].headers["Referer"], "https://www.manben.com/m2/")
    }

    func testLongAuthorLinksAndQuotedFakeClassDoNotCorruptAuthor() async throws {
        let padding = String(repeating: "x", count: 20_000)
        let html = "<div class=\"comicInfo\"><h1>作品</h1><a href=\"\(padding)\">other</a><a href=\"ignore class='avatar'\" class='other'>错误作者</a><a href=\"/search?title=<%htmlurlencode(作者)%>\" class='small avatar'>作者</a></div>"
        let source = ManbenComicSource(transport: ManbenFixtureTransport([html]))
        let detail = try await source.detail(comicId: "book")
        XCTAssertEqual(detail.author, "作者")
    }

    func testResponseCharsetDecodesNonUTF8Title() async throws {
        let source = ManbenComicSource(transport: ManbenLatinTransport())
        let detail = try await source.detail(comicId: "cafe")
        XCTAssertEqual(detail.summary.title, "Café")
    }

    func testNoNewImagesTwiceFailsWithoutRequestingMorePages() async throws {
        let image = "var chapterimage={\"ImagePix\":\"https://img.test/\",\"Images\":[\"1.jpg\"],\"IsEnd\":false};"
        let transport = ManbenFixtureTransport(["<title>章</title>", image, image, image])
        do { _ = try await ManbenComicSource(transport: transport).chapter(url: "/m2/"); XCTFail("Must reject incomplete loop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("无新增")) }
        let count = await transport.requests.count
        XCTAssertEqual(count, 4)
    }

    func testErrorShellsAndInvalidImageDataAreNotEmptySuccess() async throws {
        for html in ["<title>验证码</title>", ""] {
            let source = ManbenComicSource(transport: ManbenFixtureTransport([html, html, html, html]))
            do { _ = try await source.latest(page: 1); XCTFail("category shell") } catch {}
            do { _ = try await source.search(keyword: "x", page: 1); XCTFail("search shell") } catch {}
            do { _ = try await source.detail(comicId: "x"); XCTFail("detail shell") } catch {}
            do { _ = try await source.chapters(comicId: "x"); XCTFail("catalog shell") } catch {}
        }
        for script in ["error", "var chapterimage={\"ImagePix\":\"https://img.test/\",\"Images\":[],\"IsEnd\":true};"] {
            let source = ManbenComicSource(transport: ManbenFixtureTransport(["<title>章</title>", script]))
            do { _ = try await source.chapter(url: "/m1/"); XCTFail("invalid images") } catch {}
        }
        let blocked = ManbenFixtureTransport(["<title>章</title>章节数据缺少，已屏蔽"])
        do { _ = try await ManbenComicSource(transport: blocked).chapter(url: "/m1/"); XCTFail("blocked") } catch {}
        let count = await blocked.requests.count
        XCTAssertEqual(count, 1)
    }

    func testHTTPFailureAndCancellationPropagateWithoutMoreRequests() async throws {
        let failed = ManbenComicSource(transport: ManbenFixtureTransport(["[]"], status: 503))
        do { _ = try await failed.latest(page: 1); XCTFail("HTTP failure") }
        catch { XCTAssertEqual(error as? HTTPTransportError, .invalidStatusCode(503)) }
        let transport = ManbenFixtureTransport(["<title>章</title>"], cancelAt: 2)
        do { _ = try await ManbenComicSource(transport: transport).chapter(url: "/m1/"); XCTFail("cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        let count = await transport.requests.count
        XCTAssertEqual(count, 2)
    }

    func testSourceConfigDefaultsAndConfiguredSource() async throws {
        let def = SourceConfigDefaults.manben()
        XCTAssertEqual(def.id, "manben")
        XCTAssertEqual(def.name, "漫本")
        XCTAssertEqual(def.domain, "www.manben.com")
        XCTAssertEqual(def.baseUrl, "https://www.manben.com")
        XCTAssertEqual(def.referer, "https://www.manben.com/")
        XCTAssertEqual(def.route("latest"), "/mh-list/pagerdata.ashx")
        XCTAssertEqual(def.route("categoryIndex"), "/mh-list/")
        XCTAssertEqual(def.route("search"), "/search?page={page}&title={keyword}&language=1")
        XCTAssertEqual(def.route("detail"), "/mh-{comicId}/")
        XCTAssertEqual(def.route("chapter"), "/m{chapterId}/")
        XCTAssertEqual(def.route("chapterImages"), "/imageshow.ashx?cid={chapterId}&page={page}&showtype=1&ispre=0")
        XCTAssertEqual(SourceConfigDefaults.defaultConfig(for: "manben")?.id, "manben")

        let custom = SourceConfigItem(
            id: "manben",
            name: "漫本镜像",
            domain: "mirror.manben.com",
            baseUrl: "https://mirror.manben.com",
            referer: "https://mirror.manben.com/",
            latestPath: "/mh-list/pagerdata.ashx",
            searchPath: "/search?page={page}&title={keyword}&language=1",
            categoryPath: "/mh-list/pagerdata.ashx",
            detailPath: "/mh-{comicId}/",
            enabled: true,
            routes: [
                "latest": "/mh-list/pagerdata.ashx",
                "categoryIndex": "/mh-list/",
                "search": "/search?page={page}&title={keyword}&language=1",
                "detail": "/mh-{comicId}/"
            ],
            filters: [:]
        )
        let transport = ManbenFixtureTransport(["""
        [{"Url":"/mh-custom/","Title":"自定义漫画","BigPic":"/custom.jpg","Author":["作者"],"TagList":["奇幻"]}]
        """])
        let configured = ManbenComicSource(config: custom, transport: transport)
        let items = try await configured.latest(page: 1)
        XCTAssertEqual(items.first?.comicId, "manben:custom")
        XCTAssertEqual(items.first?.coverUrl, "https://mirror.manben.com/custom.jpg")
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url, "https://mirror.manben.com/mh-list/pagerdata.ashx")
        XCTAssertEqual(requests.first?.headers["Referer"], "https://mirror.manben.com/")
    }
}

private struct ManbenLatinTransport: HTTPTransport {
    func get(_ url: URL, headers: [String:String]) async throws -> HTTPResponse {
        .init(data: "<div class=\"comicInfo\"><h1>Café</h1></div>".data(using: .isoLatin1)!, statusCode: 200, textEncodingName: "iso-8859-1")
    }
}

private actor ManbenFixtureTransport: HTTPTransport {
    struct Request: Sendable { let method: String; let url: String; let headers: [String:String]; let body: String }
    var requests: [Request] = []
    let responses: [String]
    let status: Int
    let cancelAt: Int?
    init(_ responses: [String], status: Int = 200, cancelAt: Int? = nil) { self.responses = responses; self.status = status; self.cancelAt = cancelAt }
    func get(_ url: URL, headers: [String:String]) async throws -> HTTPResponse { try response(method: "GET", url: url, headers: headers, body: Data()) }
    func post(_ url: URL, headers: [String:String], body: Data) async throws -> HTTPResponse { try response(method: "POST", url: url, headers: headers, body: body) }
    private func response(method: String, url: URL, headers: [String:String], body: Data) throws -> HTTPResponse {
        requests.append(.init(method: method, url: url.absoluteString, headers: headers, body: String(decoding: body, as: UTF8.self)))
        if requests.count == cancelAt { throw CancellationError() }
        guard requests.count <= responses.count else { throw URLError(.resourceUnavailable) }
        return .init(data: Data(responses[requests.count - 1].utf8), statusCode: status)
    }
}
