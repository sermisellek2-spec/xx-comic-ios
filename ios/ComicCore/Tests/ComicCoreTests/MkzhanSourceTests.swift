import XCTest
@testable import ComicCore

final class MkzhanSourceTests: XCTestCase {
    private let cards = """
    <div class="cate-comic-list clearfix">
    <div class="common-comic-item" data-cid="42"><a class="cover" href="/42/"><img data-src="http://img.test/cover.jpg" alt="备用"></a>
    <p class="comic__title"><a>星&amp;海</a></p><p class="comic-update"><a>第10话<i>图标</i></a></p><p class="comic-count">999</p></div>
    <div class="common-comic-item" data-cid="42"><img alt="重复"></div>
    <div class="common-comic-item"><a class="cover" href="/7/"><img data-original="/7.jpg" alt="备用标题"></a><p class="comic-count">123</p></div>
    <div id="Pagination"></div></div><div class="common-comic-item" data-cid="999"><img alt="推荐"></div>
    """

    func testImportedAndroidQueryTemplateKeepsQuestionMarkAndPagination() async throws {
        XCTAssertEqual(SourceConfigDefaults.mkzhan().route("latest"), "/category{query}")
        XCTAssertEqual(SourceConfigDefaults.mkzhan().route("category"), "/category{query}")
        let suite = "mkzhan-config-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs)
        _ = try preferences.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"mkzhan","baseUrl":"https://fixture.invalid","routes":{"latest":"/category{query}","category":"/category{query}"}}]}"#)
        let expectedURLs = [
            "https://fixture.invalid/category?page=2",
            "https://fixture.invalid/category?is_free=1",
            "https://fixture.invalid/category?is_free=1&theme_id=9&finish=2&page=4"
        ]
        let transport = MkzhanTransport(Dictionary(uniqueKeysWithValues: expectedURLs.map { ($0, cards) }))
        let source = MkzhanComicSource(config: try XCTUnwrap(preferences.config(for: "mkzhan")), transport: transport)
        let latest = try await source.latest(page: 2)
        let first = try await source.category(filters: [:], page: 1)
        let filtered = try await source.category(filters: ["finish": "2", "theme_id": "9"], page: 4)
        XCTAssertEqual(first, latest)
        XCTAssertEqual(filtered, latest)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.0 }, expectedURLs)
        _ = try preferences.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"mkzhan","routes":{"latest":"/category{pageQuery}","category":"/category?{query}"}}]}"#)
        let legacy = MkzhanComicSource(config: try XCTUnwrap(preferences.config(for: "mkzhan")), transport: transport)
        _ = try await legacy.latest(page: 2)
        _ = try await legacy.category(filters: [:], page: 1)
        _ = try await legacy.category(filters: ["finish": "2", "theme_id": "9"], page: 4)
        let allRequests = await transport.requests
        XCTAssertEqual(allRequests.map { $0.0 }, expectedURLs + expectedURLs)
    }

    func testLatestAndCategoryDifferAndSearchOnlyRequestsPageOne() async throws {
        let transport = MkzhanTransport([
            "https://www.mkzhan.com/category?page=2": cards,
            "https://www.mkzhan.com/category?is_free=1&theme_id=9&finish=2&audience=1&copyright=3&page=4": cards,
            "https://www.mkzhan.com/search/?keyword=%E6%98%9F+%26+%7E*": cards
        ])
        let source = MkzhanComicSource(transport: transport)
        let latest = try await source.latest(page: 2)
        XCTAssertEqual(latest, [
            .init(sourceId: "mkzhan", comicId: "mkzhan:42", title: "星&海", coverUrl: "https://img.test/cover.jpg", subtitle: "第10话"),
            .init(sourceId: "mkzhan", comicId: "mkzhan:7", title: "备用标题", coverUrl: "https://www.mkzhan.com/7.jpg", subtitle: "123")
        ])
        let category = try await source.category(filters: ["copyright": "3", "audience": "1", "finish": "2", "theme_id": "9"], page: 4)
        XCTAssertEqual(category, latest)
        let search = try await source.search(keyword: " 星 & ~* ", page: 1)
        XCTAssertEqual(search, latest)
        let next = try await source.search(keyword: "anything", page: 2)
        XCTAssertEqual(next, [])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].1["Referer"], "https://www.mkzhan.com/")
        XCTAssertTrue(requests[0].1["User-Agent"]?.contains("Chrome/124.0.0.0") == true)
    }

    func testFilterLabelsAndQueryValuesFollowPageOrder() async throws {
        let html = """
        <div><div class="cate-col"><p class="cate-title">进度：</p><a href="/category">全部</a><a href="/category?finish=2&amp;is_free=1">完结</a></div>
        <div class="cate-col"><p class="cate-title">题材：</p><a href="/category">全部</a><a href="/category?theme_id=9">奇幻</a></div>
        <div class="cate-col"><p class="cate-title">受众：</p><a href="/category?audience=1">少年</a></div>
        <div class="cate-col"><p class="cate-title">版权：</p><a href="/category?copyright=3">独家</a></div></div>
        """
        let source = MkzhanComicSource(transport: MkzhanTransport(["https://www.mkzhan.com/category": html]))
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups, [
            .init(key: "finish", label: "进度", options: [.init(label: "全部", value: "all"), .init(label: "完结", value: "2")]),
            .init(key: "theme_id", label: "题材", options: [.init(label: "全部", value: "all"), .init(label: "奇幻", value: "9")]),
            .init(key: "audience", label: "受众", options: [.init(label: "少年", value: "1")]),
            .init(key: "copyright", label: "版权", options: [.init(label: "独家", value: "3")])
        ])
    }

    func testDetailHasSameResponseCatalogWithCompoundIDsAndNoReadShortcut() async throws {
        let html = """
        <h1>星&amp;海</h1><div class="de-info__cover"><img data-src="//img.test/42.jpg"></div>
        <span>作者：</span><a>作者甲</a><div class="de-chapter__title"><span>连载中</span></div>
        <span class="update-time">更新至第二话</span><p class="intro-total">介绍<br>续篇&hellip;</p>
        <a data-hreflink="/42/9.html">开始阅读</a><a data-hreflink="/42/9.html">第一话</a>
        <a data-hreflink="/42/2.html"><b>第二话</b></a><a data-hreflink="/42/9.html">重复</a>
        """
        let source = MkzhanComicSource(transport: MkzhanTransport(["https://www.mkzhan.com/42/": html]))
        let detail = try await source.detail(comicId: "mkzhan:https://old.test/42/")
        XCTAssertEqual(detail.summary.comicId, "mkzhan:42")
        XCTAssertEqual(detail.summary.coverUrl, "https://img.test/42.jpg")
        XCTAssertEqual(detail.author, "作者甲")
        XCTAssertEqual(detail.description, "介绍 续篇…")
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.latestChapter, "更新至第二话")
        XCTAssertEqual(detail.chapters, [
            .init(chapterId: "42/9", title: "第一话", url: "https://www.mkzhan.com/42/9.html", chapterSlot: 0),
            .init(chapterId: "42/2", title: "第二话", url: "https://www.mkzhan.com/42/2.html", chapterSlot: 1)
        ])
        let chapters = try await source.chapters(comicId: "42")
        XCTAssertEqual(chapters, detail.chapters)
    }

    func testReaderRequestsAPIAndUpgradesHTTPDeduplicatesImages() async throws {
        let api = "https://comic.mkzcdn.com/chapter/content/v1/?chapter_id=9&comic_id=42&quality=1&type=1&format=0&uid=&sign="
        let source = MkzhanComicSource(transport: MkzhanTransport([api: #"{"data":{"page":[{"image":"http://img.test/1.jpg?a=1&amp;b=2"},{"image":"https://img.test/2.jpg"},{"image":"https://img.test/2.jpg"},{"image":""},null]}}"#]))
        let chapter = try await source.chapter(url: "https://legacy.test/42/9.html?old=1")
        XCTAssertEqual(chapter.chapterId, "https://www.mkzhan.com/42/9.html")
        XCTAssertEqual(chapter.imageUrls, ["https://img.test/1.jpg?a=1&b=2", "https://img.test/2.jpg"])
        XCTAssertEqual(chapter.nextPageUrl, "")
    }

    func testListsRequireTargetContainerAndDoNotLeakRecommendationsWithoutPagination() async throws {
        let noPagination = """
        <div class="cate-comic-list clearfix">
        <div class="common-comic-item" data-cid="42"><img alt="正文"></div>
        </div>
        <aside><div class="common-comic-item" data-cid="999"><img alt="推荐"></div></aside>
        """
        let source = MkzhanComicSource(transport: MkzhanTransport(["https://www.mkzhan.com/category": noPagination]))
        let comics = try await source.latest(page: 1)
        XCTAssertEqual(comics.map(\.comicId), ["mkzhan:42"])

        let empty = MkzhanComicSource(transport: MkzhanTransport([
            "https://www.mkzhan.com/category": #"<div class="cate-comic-list clearfix"></div><div class="common-comic-item" data-cid="999"><img alt="推荐"></div>"#
        ]))
        let emptyComics = try await empty.latest(page: 1)
        XCTAssertEqual(emptyComics, [])

        let recommendationsOnly = MkzhanComicSource(transport: MkzhanTransport([
            "https://www.mkzhan.com/category": #"<html><head><title>临时页面</title></head><body><div class="common-comic-item" data-cid="999"><img alt="推荐"></div></body></html>"#
        ]))
        do {
            _ = try await recommendationsOnly.latest(page: 1)
            XCTFail("推荐卡片不能冒充列表")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("列表解析失败"))
        }
    }

    func testTitledErrorShellIsRejectedButStructuredEmptyCatalogIsValid() async throws {
        let errorShell = """
        <html><head><title>Access denied - 漫客栈</title></head><body>
        <h1>Access denied</h1><a data-hreflink="/42/9.html">返回首页</a>
        </body></html>
        """
        let invalid = MkzhanComicSource(transport: MkzhanTransport(["https://www.mkzhan.com/42/": errorShell]))
        do {
            _ = try await invalid.detail(comicId: "42")
            XCTFail("带标题的错误页不能冒充详情")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("详情解析失败"))
        }
        do {
            _ = try await invalid.chapters(comicId: "42")
            XCTFail("带标题的错误页不能冒充目录")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("目录解析失败"))
        }

        let emptyCatalog = """
        <h1>暂无章节</h1><div class="de-info__cover"><img data-src="/42.jpg"></div>
        <div class="de-chapter__title"><span>连载中</span></div>
        """
        let valid = MkzhanComicSource(transport: MkzhanTransport(["https://www.mkzhan.com/42/": emptyCatalog]))
        let detail = try await valid.detail(comicId: "42")
        let chapters = try await valid.chapters(comicId: "42")
        XCTAssertEqual(detail.chapters, [])
        XCTAssertEqual(chapters, [])
    }

    func testPreCancelledRequestDoesNotReachTransport() async {
        let transport = MkzhanTransport([:])
        let source = MkzhanComicSource(transport: transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await source.latest(page: 1)
        }

        do {
            _ = try await task.value
            XCTFail("预取消任务不应继续请求")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 0)
    }

    func testErrorShellAndHTTPFailureAreNotEmptySuccess() async throws {
        let source = MkzhanComicSource(transport: MkzhanTransport(["https://www.mkzhan.com/category": "<html>error</html>", "https://www.mkzhan.com/42/": "<html>error</html>"]))
        do { _ = try await source.latest(page: 1); XCTFail("shell") } catch { XCTAssertTrue(error.localizedDescription.contains("解析失败")) }
        do { _ = try await source.detail(comicId: "42"); XCTFail("shell") } catch { XCTAssertTrue(error.localizedDescription.contains("解析失败")) }
        let failure = MkzhanComicSource(transport: MkzhanTransport(["https://www.mkzhan.com/category": cards], status: 403))
        do { _ = try await failure.latest(page: 1); XCTFail("HTTP") } catch { XCTAssertEqual(error as? HTTPTransportError, .invalidStatusCode(403)) }
    }
}

private actor MkzhanTransport: HTTPTransport {
    let responses: [String: String]
    let status: Int
    var requests: [(String, [String: String])] = []
    init(_ responses: [String: String], status: Int = 200) { self.responses = responses; self.status = status }
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append((url.absoluteString, headers))
        guard let html = responses[url.absoluteString] else { throw URLError(.badURL) }
        return HTTPResponse(data: Data(html.utf8), statusCode: status)
    }
}
