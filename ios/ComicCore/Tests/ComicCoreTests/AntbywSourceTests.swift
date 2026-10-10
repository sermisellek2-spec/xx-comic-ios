import XCTest
@testable import ComicCore

final class AntbywSourceTests: XCTestCase {
    private let cards = """
    <div class="uk-card uk-text-center"><a href="plugin.php?id=jameson_manhua&amp;c=index&amp;a=bofang&amp;kuid=42"><img data-src="/mh_cover/a.jpg"></a><p><a href="plugin.php?id=jameson_manhua&amp;a=bofang&amp;kuid=42">星&amp;海</a></p><a href="plugin.php?a=bofang&amp;kuid=42">阅读 99</a></div>
    <div class="uk-card uk-text-center"><a href="plugin.php?a=bofang&amp;kuid=42"><img src="/dup.jpg"></a><p><a href="plugin.php?a=bofang&amp;kuid=42">重复</a></p></div>
    <footer></footer>
    """

    func testLatestSearchFiltersAndCategoryPreserveURLsFieldOrderAndIdentity() async throws {
        let filtersHTML = """
        <div class="cl"><strong>分类</strong><a data-field="category_id" data-value="empty">全部</a><a data-field="category_id" data-value="7">奇幻&amp;冒险</a></div>
        <div class="cl"><strong>进度</strong><a data-field="jindu" data-value="empty">全部</a><a data-field="jindu" data-value="2">完结</a></div>
        <div class="cl"><strong>地区</strong><a data-field="region" data-value="3">韩国</a></div>
        <div class="cl"><strong>首字母</strong><a data-field="letter" data-value="A">A</a></div>
        <div class="cl"><strong>年份</strong><a data-field="search_age" data-value="2026">2026</a></div>
        <div class="cl"><strong>受众</strong><a data-field="shouzhong" data-value="1">少年</a></div>
        """
        let latestURL = "https://www.antbyw.com/plugin.php?id=jameson_manhua&c=index&a=ku&odfie=addtime&order=desc&page=2"
        let searchURL = "https://www.antbyw.com/plugin.php?id=jameson_manhua&a=search&c=index&keyword=%E6%98%9F+%26+%7E*"
        let categoryURL = "https://www.antbyw.com/plugin.php?id=jameson_manhua&c=index&a=ku&category_id=7&jindu=2&region=3&letter=A&search_age=2026&shouzhong=1&odfie=views&order=desc&page=4"
        let transport = AntbywTransport([
            latestURL: antResponse(cards), searchURL: antResponse(cards),
            "https://www.antbyw.com/plugin.php?id=jameson_manhua&a=ku": antResponse(filtersHTML), categoryURL: antResponse(cards)
        ])
        let source = AntbywComicSource(transport: transport)
        let latest = try await source.latest(page: 2)
        XCTAssertEqual(latest, [.init(sourceId: "antbyw", comicId: "antbyw:42", title: "星&海", coverUrl: "https://www.antbyw.com/mh_cover/a.jpg", subtitle: "阅读 99")])
        let searched = try await source.search(keyword: " 星 & ~* ", page: 1)
        XCTAssertEqual(searched, latest)
        let skipped = try await source.search(keyword: "ignored", page: 2)
        XCTAssertEqual(skipped, [])
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups.map(\.key), ["category_id", "jindu", "region", "letter", "search_age", "shouzhong", "sort"])
        XCTAssertEqual(groups.map(\.label), ["题材", "进度", "地区", "字母", "年份", "受众", "排序"])
        XCTAssertEqual(groups[0].options, [.init(label: "全部", value: "all"), .init(label: "奇幻&冒险", value: "7")])
        XCTAssertEqual(groups.last?.options, [.init(label: "上架时间", value: "addtime:asc"), .init(label: "更新时间", value: "edittime:desc"), .init(label: "阅读量", value: "views:desc"), .init(label: "收藏量", value: "favores:desc")])
        let category = try await source.category(filters: ["category_id": "7", "jindu": "2", "region": "3", "letter": "A", "search_age": "2026", "shouzhong": "1", "sort": "views:desc"], page: 4)
        XCTAssertEqual(category, latest)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].headers["Accept-Language"], "zh-CN,zh;q=0.9")
    }

    func testDetailAndCatalogPreserveSectionReverseOrderDedupAndLazyContract() async throws {
        let html = """
        <!-- 作品信息 内容栏 开始 --><h3 class="uk-heading-line">星&amp;海</h3><div>漫畫作者 : 甲&amp;乙</div><a href="?jindu=1">连载中</a><div class="uk-alert">故事 &hellip; 继续</div><a href="?a=ku">奇幻</a><a href="?a=ku">奇幻</a><div>更新到 : 第3话</div><!-- 作品信息 内容栏 结束 -->
        <img src="/mh_cover/42.jpg">
        <!-- 单话内容 开始 --><a href="plugin.php?a=read&amp;kuid=42&amp;zjid=3" class="zj-container">第3话</a><a href="plugin.php?a=read&amp;kuid=42&amp;zjid=1" class="zj-container">第1话</a><!-- 单话内容 结束 -->
        <!-- 番外篇 展示栏 开始 --><a href="plugin.php?a=read&amp;kuid=42&amp;zjid=9" class="zj-container">番外9</a><a href="plugin.php?a=read&amp;kuid=42&amp;zjid=3" class="zj-container">重复3</a><!-- 番外篇 展示栏 结束 -->
        """
        let url = "https://www.antbyw.com/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid=42"
        let transport = AntbywTransport([url: antResponse(html)])
        let source = AntbywComicSource(transport: transport)
        let detail = try await source.detail(comicId: "antbyw:https://old/?kuid=42")
        XCTAssertEqual(detail.summary, .init(sourceId: "antbyw", comicId: "antbyw:42", title: "星&海", coverUrl: "https://www.antbyw.com/mh_cover/42.jpg", subtitle: "甲&乙", tags: ["奇幻"]))
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.description, "故事 … 继续")
        XCTAssertEqual(detail.latestChapter, "第3话")
        XCTAssertEqual(detail.chapters, [])
        let detailRequestCount = await transport.count()
        XCTAssertEqual(detailRequestCount, 1)
        let chapters = try await source.chapters(comicId: "antbyw:42")
        XCTAssertEqual(chapters.map(\.chapterId), ["1", "3", "9"])
        XCTAssertEqual(chapters.map(\.sectionSlot), [0, 0, 1])
        XCTAssertEqual(chapters.map(\.chapterSlot), [0, 1, 2])
        XCTAssertEqual(chapters[0].url, "https://www.antbyw.com/plugin.php?a=read&kuid=42&zjid=1")
    }

    func testReaderStripsExistingPageLoadsAllPagesAndDeduplicatesImages() async throws {
        let base = "https://www.antbyw.com/plugin.php?a=read&kuid=42&zjid=3"
        let first = "<h3 class=\"uk-heading-line\"><span>第3话&amp;上</span></h3><a href=\"?a=read&amp;kuid=42&amp;zjid=3&amp;page=3\">3</a><script>let urls = [\"/1.jpg\",\"//img.test/2.webp\"];</script>"
        let second = "<script>const urls = [\"//img.test/2.webp\",\"/3.png\"];</script>"
        let third = "<script>var urls = [];</script>"
        let transport = AntbywTransport([base + "&page=1": antResponse(first), base + "&page=2": antResponse(second), base + "&page=3": antResponse(third)])
        let page = try await AntbywComicSource(transport: transport).chapter(url: base + "&page=8")
        XCTAssertEqual(page.chapterId, base)
        XCTAssertEqual(page.title, "第3话&上")
        XCTAssertEqual(page.imageUrls, ["https://www.antbyw.com/1.jpg", "https://img.test/2.webp", "https://www.antbyw.com/3.png"])
        let requestedURLs = await transport.urls()
        XCTAssertEqual(requestedURLs, [base + "&page=1", base + "&page=2", base + "&page=3"])
    }

    func testValidEmptyListDiffersFromShellAndErrorsPropagate() async throws {
        let validURL = "https://www.antbyw.com/plugin.php?id=jameson_manhua&c=index&a=ku&odfie=addtime&order=desc&page=1"
        let valid = AntbywComicSource(transport: AntbywTransport([validURL: antResponse("<div class='shaixuancont'></div><div class='uk-grid'></div>")]))
        let empty = try await valid.latest(page: 1)
        XCTAssertEqual(empty, [])
        let shell = AntbywComicSource(transport: AntbywTransport([validURL: antResponse("<html><h1>Rate limited</h1></html>")]))
        await XCTAssertAntbywThrows(try await shell.latest(page: 1)) { XCTAssertNotNil($0 as? AntbywSourceError) }
        let status = AntbywComicSource(transport: AntbywTransport([validURL: antResponse(cards, status: 503)]))
        await XCTAssertAntbywThrows(try await status.latest(page: 1)) { XCTAssertEqual($0 as? HTTPTransportError, .invalidStatusCode(503)) }
        let cancelled = AntbywComicSource(transport: AntbywCancelledTransport())
        await XCTAssertAntbywThrows(try await cancelled.latest(page: 1)) { XCTAssertTrue($0 is CancellationError) }
    }

    func testCatalogSupportsAndroidSingleChapterSectionFallback() async throws {
        let html = "<!-- 单话 展示栏 开始 --><a href='plugin.php?a=read&amp;kuid=5&amp;zjid=2' class='zj-container'>第2话</a><a href='plugin.php?a=read&amp;kuid=5&amp;zjid=1' class='zj-container'>第1话</a><!-- 单话 展示栏 结束 -->"
        let url = "https://www.antbyw.com/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid=5"
        let chapters = try await AntbywComicSource(transport: AntbywTransport([url: antResponse(html)])).chapters(comicId: "5")
        XCTAssertEqual(chapters.map(\.chapterId), ["1", "2"])
    }

    func testSourceConfigDefaultsAndConfiguredSource() async throws {
        let def = SourceConfigDefaults.antbyw()
        XCTAssertEqual(def.id, "antbyw")
        XCTAssertEqual(def.name, "tapmanga搬运")
        XCTAssertEqual(def.domain, "www.antbyw.com")
        XCTAssertEqual(def.baseUrl, "https://www.antbyw.com")
        XCTAssertEqual(def.referer, "https://www.antbyw.com/")
        XCTAssertEqual(def.route("latest"), "/plugin.php?id=jameson_manhua&c=index&a=ku")
        XCTAssertEqual(def.route("search"), "/plugin.php?id=jameson_manhua&a=search&c=index&keyword={keyword}")
        XCTAssertEqual(def.route("categoryIndex"), "/plugin.php?id=jameson_manhua&a=ku")
        XCTAssertEqual(def.route("category"), "/plugin.php?id=jameson_manhua&c=index&a=ku")
        XCTAssertEqual(def.route("detail"), "/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid={comicId}")
        XCTAssertEqual(SourceConfigDefaults.defaultConfig(for: "antbyw")?.id, "antbyw")

        let custom = SourceConfigItem(
            id: "antbyw",
            name: "蚂蚁镜像",
            domain: "mirror.antbyw.com",
            baseUrl: "https://mirror.antbyw.com",
            referer: "https://mirror.antbyw.com/",
            latestPath: "/plugin.php?id=jameson_manhua&c=index&a=ku",
            searchPath: "/plugin.php?id=jameson_manhua&a=search&c=index&keyword={keyword}",
            categoryPath: "/plugin.php?id=jameson_manhua&c=index&a=ku",
            detailPath: "/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid={comicId}",
            enabled: true,
            routes: [
                "search": "/plugin.php?id=jameson_manhua&a=search&c=index&keyword={keyword}",
                "detail": "/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid={comicId}"
            ],
            filters: [:]
        )
        let searchURL = "https://mirror.antbyw.com/plugin.php?id=jameson_manhua&a=search&c=index&keyword=%E7%8E%8B"
        let transport = AntbywTransport([searchURL: antResponse(cards)])
        let configured = AntbywComicSource(config: custom, transport: transport)
        XCTAssertEqual(configured.id, "antbyw")
        XCTAssertEqual(configured.name, "蚂蚁镜像")
        XCTAssertEqual(configured.referer, "https://mirror.antbyw.com/")
        let search = try await configured.search(keyword: "王", page: 1)
        XCTAssertEqual(search.count, 1)
        let reqs = await transport.requests
        XCTAssertEqual(reqs.first?.url, searchURL)
        XCTAssertEqual(reqs.first?.headers["Referer"], "https://mirror.antbyw.com/")
    }
}

private struct AntbywRequest: Sendable { let url: String; let headers: [String: String] }
private actor AntbywTransport: HTTPTransport {
    let responses: [String: HTTPResponse]; var requests: [AntbywRequest] = []
    init(_ responses: [String: HTTPResponse]) { self.responses = responses }
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse { requests.append(.init(url: url.absoluteString, headers: headers)); guard let response = responses[url.absoluteString] else { throw URLError(.badURL) }; return response }
    func count() -> Int { requests.count }
    func urls() -> [String] { requests.map(\.url) }
}
private struct AntbywCancelledTransport: HTTPTransport { func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse { throw CancellationError() } }
private func antResponse(_ body: String, status: Int = 200) -> HTTPResponse { .init(data: Data(body.utf8), statusCode: status) }
private func XCTAssertAntbywThrows<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void, file: StaticString = #filePath, line: UInt = #line) async { do { _ = try await expression(); XCTFail("Expected throw", file: file, line: line) } catch { handler(error) } }
