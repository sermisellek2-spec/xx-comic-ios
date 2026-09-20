import Foundation
import XCTest
@testable import ComicCore

final class CuimhSourceTests: XCTestCase {
    private let categoryHTML = """
    <div class="cy_tag"><span>分类</span><ul><li><a href="/category/">全部</a></li><li><a href="/category/list/1">国产漫画</a></li></ul></div>
    <div class="cy_list_mh"><ul><li><a href="/yirenzhixia_260264" class="pic"><img src="https://img.test/cover.webp" alt="错误标题"></a></li><li class="title"><a href="/yirenzhixia_260264">一人&amp;之下</a></li><li class="zuozhe">状态：连载中</li><li class="biaoqian"><a>冒险</a><a>热血</a><a>冒险</a></li></ul></div>
    """

    func testLatestParsesScopedCardsAndUsesPagePathAndHeaders() async throws {
        let recommendations = categoryHTML.replacingOccurrences(of: "yirenzhixia_260264", with: "recommendation")
        let transport = CuimhTransport(defaultResponse: .html(categoryHTML + recommendations))
        let source = makeSource(transport: transport)

        let comics = try await source.latest(page: 2)

        XCTAssertEqual(comics, [.init(sourceId: "cuimh", comicId: "cuimh:yirenzhixia_260264", title: "一人&之下", coverUrl: "https://img.test/cover.webp", subtitle: "连载中", tags: ["冒险", "热血"])])
        let recorded = await transport.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.0, "https://www.cuimh.com/category/page/2")
        XCTAssertEqual(request.1["Referer"], "https://www.cuimh.com/")
        XCTAssertEqual(request.1["Accept-Language"], "zh-CN,zh;q=0.9")
        XCTAssertTrue(request.1["User-Agent"]?.contains("Chrome/124.0.0.0") == true)
    }

    func testFiltersKeepSupportedGroupsAndComposeOnlyMatchingPrefixesInFixedOrder() async throws {
        let html = """
        \(filter("进度", [("全部", "/category/"), ("连载", "/category/finish/1")]))
        \(filter("标签", [("全部", "/category/"), ("热血", "/category/tags/2572"), ("热血", "/category/tags/9999")]))
        \(filter("资费", [("免费", "/category/pay/1")]))
        \(filter("分类", [("国产漫画", "/category/list/1")]))
        <div class="cy_list_mh"></div>
        """
        let transport = CuimhTransport(responses: [
            "https://www.cuimh.com/category/": [.html(html)],
            "https://www.cuimh.com/category/list/1/tags/2572/finish/1/page/2": [.html(categoryHTML)]
        ])
        let source = makeSource(transport: transport)

        let groups = try await source.filterGroups()
        XCTAssertEqual(groups.map(\.key), ["state", "subject", "classification"])
        XCTAssertEqual(groups.map(\.label), ["状态", "题材", "分类"])
        XCTAssertEqual(groups[1].options, [.init(label: "全部", value: "all"), .init(label: "热血", value: "/tags/2572")])
        let comics = try await source.category(filters: [
            "state": "/finish/1", "subject": "/tags/2572", "classification": "/list/1",
            "type": "/tags/should-not-match", "quality": "/evil/1"
        ], page: 2)
        XCTAssertEqual(comics.count, 1)
    }

    func testDetailIncludesDeduplicatedChaptersFromTheSameDocument() async throws {
        let html = """
        <div class="cy_info_cover"><img src="/cover/tree.jpg"></div><div class="cy_title"><h1>从大树开始的进化</h1></div>
        <span class="cy_author">作者：<a>黑&amp;鸟社</a></span><span class="cy_type"><a>异能</a><a>格斗</a></span>
        <span class="cy_serialize">状态：<font>连载中</font></span><span class="cy_newpic">最新话：<a>第528话</a></span>
        <p id="comic-description">重生成一株柳树&hellip;</p>
        <li class="chapter__item"><a href="/419013-227267.html"><p>第528话</p></a></li>
        <li class="chapter__item"><a href="/419013-227234.html"><p>第527话</p></a></li>
        <li class="chapter__item"><a href="/419013-227267.html"><p>重复</p></a></li>
        """
        let transport = CuimhTransport(responses: ["https://www.cuimh.com/tree": [.html(html)]])
        let detail = try await makeSource(transport: transport).detail(comicId: "cuimh:https://old.test/tree?x=1")

        XCTAssertEqual(detail.summary, .init(sourceId: "cuimh", comicId: "cuimh:tree", title: "从大树开始的进化", coverUrl: "https://www.cuimh.com/cover/tree.jpg", subtitle: "黑&鸟社", tags: ["异能", "格斗"]))
        XCTAssertEqual(detail.author, "黑&鸟社")
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.description, "重生成一株柳树…")
        XCTAssertEqual(detail.latestChapter, "第528话")
        XCTAssertEqual(detail.chapters.map(\.chapterId), ["419013-227267", "419013-227234"])
        XCTAssertEqual(detail.chapters.map(\.chapterSlot), [0, 1])
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testCatalogChapterIDsExcludeQueryAndFragment() async throws {
        for suffix in ["#reader", "?mode=1#reader", "#reader/position?mode=1"] {
            let html = "<li class='chapter__item'><a href='/419013-227267.html\(suffix)'>第528话</a></li>"
            let source = makeSource(transport: CuimhTransport(defaultResponse: .html(html)))
            let chapters = try await source.chapters(comicId: "tree")
            XCTAssertEqual(chapters.map(\.chapterId), ["419013-227267"], suffix)
        }
    }

    func testChapterDecryptsFixedAndroidFixtureAndNormalizesRelativeImages() async throws {
        let payload = "MDEyMzQ1Njc4OWFiY2RlZutEhySNBDxh7+9pX7lLguDwdPqtjE0tJLVG7+xCkHDt8wNN7cqhoHcwG3tUWN0IQwe7JEqUHI+AXvzwvUk6n4EgljPPb5F5MAJn2Knj9EpWbv2K8oHdIjj7c8x5IkNvnFDCV2qy8rDuJUDhSUFw4lU="
        let html = "<title>第528话-下拉式阅读</title><script>params = '\(payload)'</script>"
        let transport = CuimhTransport(responses: ["https://www.cuimh.com/419013-227267.html": [.html(html)]])

        let page = try await makeSource(transport: transport).chapter(url: "/419013-227267.html")

        XCTAssertEqual(page.chapterId, "https://www.cuimh.com/419013-227267.html")
        XCTAssertEqual(page.title, "第528话")
        XCTAssertEqual(page.nextPageUrl, "")
        XCTAssertEqual(page.imageUrls, ["https://img.example/1.webp", "https://img1.baipiaoguai.org/static/2.webp"])
    }

    func testSearchIsExplicitlyUnsupportedWithoutNetwork() async throws {
        let transport = CuimhTransport(defaultResponse: .html(categoryHTML))
        let source = makeSource(transport: transport)
        XCTAssertFalse(source.supportsSearch)
        do { _ = try await source.search(keyword: "一人之下", page: 1); XCTFail("搜索不应成功") }
        catch { XCTAssertTrue(error.localizedDescription.contains("不支持搜索")) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testDefaultCategoryAliasesShareFiveMinuteCacheWithExclusiveBoundary() async throws {
        let clock = TestMillisecondsClock()
        let transport = CuimhTransport(defaultResponse: .html(categoryHTML))
        let source = makeSource(transport: transport, clock: clock)

        _ = try await source.latest(page: 1)
        clock.advance(by: 299_999)
        _ = try await source.filterGroups()
        var requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
        clock.advance(by: 1)
        _ = try await source.latest(page: 1)
        requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 2)
    }

    func testCategoryCacheUsesLRUEvictionAtEightDocuments() async throws {
        let clock = TestMillisecondsClock()
        let transport = CuimhTransport(defaultResponse: .html(categoryHTML))
        let source = makeSource(transport: transport, clock: clock)
        for page in 1...8 { _ = try await source.latest(page: page) }
        _ = try await source.latest(page: 1)
        _ = try await source.latest(page: 9)
        _ = try await source.latest(page: 2)

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 10)
        XCTAssertEqual(requests.filter { $0.0.hasSuffix("/category/page/2") }.count, 2)
    }

    func testConcurrentOriginRequestsRemainSerializedAndStartOneSecondApart() async throws {
        let clock = TestMillisecondsClock()
        let transport = CuimhTransport(defaultResponse: .html(categoryHTML), clock: clock, yields: 30)
        let source = makeSource(transport: transport, clock: clock)

        async let first = source.category(filters: ["subject": "/tags/1"], page: 1)
        async let second = source.category(filters: ["subject": "/tags/2"], page: 1)
        _ = try await (first, second)

        let maxActive = await transport.maxActiveRequests
        XCTAssertEqual(maxActive, 1)
        let starts = await transport.startedAt
        XCTAssertEqual(starts.count, 2)
        XCTAssertGreaterThanOrEqual(abs(starts[1] - starts[0]), 1_000)
    }

    func testForbiddenCooldownPrecedesCacheAndExpiresAtThirtyMinutes() async throws {
        let clock = TestMillisecondsClock()
        let transport = CuimhTransport(responses: [
            "https://www.cuimh.com/category/": [.html(categoryHTML), .html(categoryHTML)],
            "https://www.cuimh.com/category/page/2": [.html("", status: 403)]
        ], clock: clock)
        let source = makeSource(transport: transport, clock: clock)
        _ = try await source.latest(page: 1)
        do { _ = try await source.latest(page: 2); XCTFail("403 不应成功") } catch {}
        do { _ = try await source.latest(page: 1); XCTFail("冷却期间不应读取缓存") }
        catch { XCTAssertTrue(error.localizedDescription.contains("访问受限")) }
        var requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 2)

        clock.advance(by: 1_800_000)
        _ = try await source.latest(page: 1)
        requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 3)
    }

    func testCancelledForbiddenResponseStillBlocksCachedAndUncachedRequests() async throws {
        let clock = TestMillisecondsClock()
        let transport = CuimhTransport(responses: [
            "https://www.cuimh.com/category/page/2": [.html("", status: 403)]
        ], defaultResponse: .html(categoryHTML), cancelOnForbidden: true)
        let source = makeSource(transport: transport, clock: clock)
        _ = try await source.latest(page: 1)
        let request = Task { try await source.latest(page: 2) }
        do { _ = try await request.value; XCTFail("取消必须传播") }
        catch { XCTAssertTrue(error is CancellationError) }
        for page in [1, 3] {
            do { _ = try await source.latest(page: page); XCTFail("取消后仍须保留403冷却：\(page)") }
            catch { XCTAssertTrue(error.localizedDescription.contains("访问受限")) }
        }
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 2)
        clock.advance(by: 1_800_000)
        let comics = try await source.latest(page: 1)
        XCTAssertEqual(comics.count, 1)
        let countAfterExpiry = await transport.requests.count
        XCTAssertEqual(countAfterExpiry, 3)
    }

    func testWaitCancellationPropagatesAndDoesNotIssueSecondRequest() async throws {
        let clock = TestMillisecondsClock()
        let transport = CuimhTransport(defaultResponse: .html(categoryHTML))
        let source = CuimhComicSource(transport: transport, nowMilliseconds: { clock.now() }) { _ in throw CancellationError() }
        _ = try await source.latest(page: 1)
        do { _ = try await source.latest(page: 2); XCTFail("取消不应成功") }
        catch { XCTAssertTrue(error is CancellationError) }
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testMalformedShellAndEmptyStandaloneCatalogAreRejected() async throws {
        let shell = "<html><h1>Access denied</h1></html>"
        let transport = CuimhTransport(responses: [
            "https://www.cuimh.com/category/": [.html(shell)],
            "https://www.cuimh.com/bad": [.html(shell)],
            "https://www.cuimh.com/empty": [.html("<div class='cy_title'><h1>空目录</h1></div>")]
        ])
        let source = makeSource(transport: transport)
        do { _ = try await source.latest(page: 1); XCTFail("错误壳不应作为空列表") } catch {}
        do { _ = try await source.detail(comicId: "bad"); XCTFail("通用 h1 不应作为详情") } catch {}
        do { _ = try await source.chapters(comicId: "empty"); XCTFail("空目录不应成功") }
        catch { XCTAssertTrue(error.localizedDescription.contains("目录")) }
    }

    private func makeSource(transport: CuimhTransport, clock: TestMillisecondsClock = TestMillisecondsClock()) -> CuimhComicSource {
        CuimhComicSource(transport: transport, nowMilliseconds: { clock.now() }) { milliseconds in
            try Task.checkCancellation()
            clock.advance(by: milliseconds)
        }
    }

    private func filter(_ label: String, _ options: [(String, String)]) -> String {
        "<div class=\"cy_tag\"><span>\(label)</span><ul>" + options.map { "<li><a href=\"\($0.1)\">\($0.0)</a></li>" }.joined() + "</ul></div>"
    }
}

private final class TestMillisecondsClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0
    func now() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func advance(by milliseconds: Int64) {
        lock.lock()
        value += milliseconds
        lock.unlock()
    }
}

private actor CuimhTransport: HTTPTransport {
    var responses: [String: [HTTPResponse]]
    let defaultResponse: HTTPResponse?
    let clock: TestMillisecondsClock?
    let yields: Int
    let cancelOnForbidden: Bool
    var requests: [(String, [String: String])] = []
    var startedAt: [Int64] = []
    var activeRequests = 0
    var maxActiveRequests = 0

    init(responses: [String: [HTTPResponse]] = [:], defaultResponse: HTTPResponse? = nil, clock: TestMillisecondsClock? = nil, yields: Int = 0, cancelOnForbidden: Bool = false) {
        self.responses = responses
        self.defaultResponse = defaultResponse
        self.clock = clock
        self.yields = yields
        self.cancelOnForbidden = cancelOnForbidden
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append((url.absoluteString, headers))
        startedAt.append(clock?.now() ?? 0)
        activeRequests += 1
        maxActiveRequests = max(maxActiveRequests, activeRequests)
        defer { activeRequests -= 1 }
        for _ in 0..<yields { await Task.yield() }
        if var queue = responses[url.absoluteString], !queue.isEmpty {
            let response = queue.removeFirst()
            responses[url.absoluteString] = queue
            if cancelOnForbidden && response.statusCode == 403 { withUnsafeCurrentTask { $0?.cancel() } }
            return response
        }
        guard let defaultResponse else { throw URLError(.badURL) }
        return defaultResponse
    }
}

extension HTTPResponse {
    static func html(_ value: String, status: Int = 200) -> HTTPResponse {
        .init(data: Data(value.utf8), statusCode: status, textEncodingName: "utf-8")
    }
}
