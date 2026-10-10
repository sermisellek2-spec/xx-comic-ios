import XCTest
@testable import ComicCore

final class FiveUmSourceTests: XCTestCase {
    private let cards = """
    <div class="comic-list"><div class="comic-item">
    <a href="/comic_42.html"><img data-src="//img.test/a.jpg?a=1&amp;b=2" src="placeholder" alt="星&amp;海&hellip;"></a>
    <p class="comic-author">作者 <b>甲</b></p></div>
    <div class="comic-item"><a href="/comic_42.html"><img alt="重复"></a></div>
    <div class="comic-item"><a href="/comic_7.html" title="第二本"><img data-original="/cover.png"></a></div></div>
    """

    func testBothSitesKeepIdentityHeadersPaginationAndFormSearch() async throws {
        for (site, base, id) in [(FiveUmComicSource.Site.manhuazhan, "https://www.60ti.com", "manhuazhan"), (.bbyin, "https://bbyin.com", "bbyin")] {
            let transport = FiveUmTransport([
                base + "/category/page/2": cards,
                base + "/search?key=%E6%98%9F+%26+%7E*": cards
            ])
            let source = FiveUmComicSource(site: site, transport: transport)
            let latest = try await source.latest(page: 2)
            XCTAssertEqual(latest.map(\.comicId), [id + ":42", id + ":7"])
            XCTAssertEqual(latest.map(\.title), ["星&海…", "第二本"])
            XCTAssertEqual(latest[0].coverUrl, "https://img.test/a.jpg?a=1&b=2")
            XCTAssertEqual(latest[1].coverUrl, base + "/cover.png")
            XCTAssertEqual(latest[0].subtitle, "作者 甲")
            let search = try await source.search(keyword: " 星 & ~* ", page: 1)
            XCTAssertEqual(search, latest)
            let beyondFirst = try await source.search(keyword: "ignored", page: 2)
            XCTAssertEqual(beyondFirst, [])
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 2)
            XCTAssertEqual(requests[0].1["Referer"], base + "/")
            XCTAssertEqual(requests[0].1["Accept-Language"], "zh-CN,zh;q=0.9")
            XCTAssertTrue(requests[0].1["User-Agent"]?.contains("Chrome/124.0.0.0") == true)
        }
    }

    func testFiltersIgnoreOtherSectionsDeduplicateAndComposeStatePage() async throws {
        let html = """
        <div class="filter-section">其他<a href="/category/tags/999">忽略</a></div>
        <div class="filter-section">漫画类型
        <a href="/category/tags/1/">热血</a><a href="/category/tags/2">奇幻&amp;冒险</a>
        <a href="/category/tags/3">热血</a><a href="/category/tags/0">全部</a></div>
        <div class="comic-list"></div>
        """
        let transport = FiveUmTransport([
            "https://www.60ti.com/category/": html,
            "https://www.60ti.com/category/tags/2/finish/2/page/3": cards,
            "https://www.60ti.com/category": "<div class='comic-list'></div>"
        ])
        let source = FiveUmComicSource(transport: transport)
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups, [
            .init(key: "category", label: "题材", options: [.init(label: "全部", value: "all"), .init(label: "热血", value: "/category/tags/1"), .init(label: "奇幻&冒险", value: "/category/tags/2")]),
            .init(key: "state", label: "状态", options: [.init(label: "全部", value: "all"), .init(label: "连载中", value: "1"), .init(label: "已完结", value: "2")])
        ])
        let category = try await source.category(filters: ["category": "/category/tags/2", "state": "2"], page: 3)
        XCTAssertEqual(category.count, 2)
        let empty = try await source.category(filters: ["category": "", "state": ""], page: 1)
        XCTAssertTrue(empty.isEmpty)
    }

    func testDetailAndSeparateCatalogPreserveDocumentOrderAndDoNotPreload() async throws {
        let html = """
        <h1>《 星&amp;海 》</h1><div class="comic-cover-large"><img data-original="/cover.jpg"></div>
        <div class="comic-main-info"><span>作者：甲&amp;乙</span>
        <div class="comic-tags"><span class="tag">奇幻</span><span class="tag">已完结</span><span class="tag">奇幻</span></div></div>
        <div class="comic-description"><p>故事<br>续篇&hellip;</p></div>
        <a href="/chapter_42_20.html">第一话</a><a href="/chapter_42_3.html">第二话</a>
        <a href="/chapter_42_20.html">重复</a>
        """
        let transport = FiveUmTransport(["https://www.60ti.com/comic_42.html": html])
        let source = FiveUmComicSource(transport: transport)
        let detail = try await source.detail(comicId: "manhuazhan:https://old.test/comic_42.html?old=1")
        XCTAssertEqual(detail.summary, .init(sourceId: "manhuazhan", comicId: "manhuazhan:42", title: "星&海", coverUrl: "https://www.60ti.com/cover.jpg", subtitle: "甲&乙", tags: ["奇幻", "已完结"]))
        XCTAssertEqual(detail.status, "已完结")
        XCTAssertEqual(detail.description, "故事 续篇…")
        XCTAssertEqual(detail.latestChapter, "第二话")
        XCTAssertEqual(detail.chapters, [])
        let before = await transport.requests.count
        XCTAssertEqual(before, 1)
        let chapters = try await source.chapters(comicId: "manhuazhan:42")
        XCTAssertEqual(chapters, [.init(chapterId: "20", title: "第一话", url: "https://www.60ti.com/chapter_42_20.html", chapterSlot: 0), .init(chapterId: "3", title: "第二话", url: "https://www.60ti.com/chapter_42_3.html", chapterSlot: 1)])
    }

    func testReaderUsesOnlyBodyImagesWithLazyPriorityAndDeduplication() async throws {
        let html = """
        <h1>《 第一话 》</h1><img class="comic-image" src="/ad.jpg">
        <div class="comic-content"><img src="/noise.jpg">
        <img class="comic-image other" data-src="//img.test/1.jpg" data-original="/wrong.jpg" src="/placeholder.jpg">
        <img class="comic-image" data-original="/2.jpg?a=1&amp;b=2">
        <img class="comic-image" src="//img.test/1.jpg"></div>
        <img class="comic-image" src="/recommend.jpg">
        """
        let transport = FiveUmTransport(["https://bbyin.com/chapter_42_20.html": html])
        let page = try await FiveUmComicSource(site: .bbyin, transport: transport).chapter(url: "/chapter_42_20.html")
        XCTAssertEqual(page.title, "第一话")
        XCTAssertEqual(page.chapterId, "https://bbyin.com/chapter_42_20.html")
        XCTAssertEqual(page.nextPageUrl, "")
        XCTAssertEqual(page.imageUrls, ["https://img.test/1.jpg", "https://bbyin.com/2.jpg?a=1&b=2"])
    }

    func testMissingContentAndHTTPErrorsAreNotSuccess() async throws {
        let transport = FiveUmTransport(["https://www.60ti.com/category": "<html>bad gateway</html>", "https://www.60ti.com/category/": "<div class='filter-section'>其他</div>", "https://www.60ti.com/comic_42.html": "<html>bad gateway</html>", "https://www.60ti.com/chapter_42_1.html": "<div class='comic-content'></div>"])
        let source = FiveUmComicSource(transport: transport)
        do { _ = try await source.latest(page: 1); XCTFail("error shell accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("解析失败")) }
        do { _ = try await source.filterGroups(); XCTFail("missing filters accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("分类")) }
        do { _ = try await source.detail(comicId: "42"); XCTFail("missing title accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("标题")) }
        do { _ = try await source.chapter(url: "/chapter_42_1.html"); XCTFail("missing images accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("正文图片")) }
        let failed = FiveUmComicSource(transport: FiveUmTransport(["https://www.60ti.com/category": cards], status: 503))
        do { _ = try await failed.latest(page: 1); XCTFail("HTTP failure accepted") } catch { XCTAssertEqual(error as? HTTPTransportError, .invalidStatusCode(503)) }
    }

    func testCancellationIsPropagated() async throws {
        let source = FiveUmComicSource(transport: FiveUmCancelledTransport())
        do { _ = try await source.latest(page: 1); XCTFail("cancel accepted") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSourceConfigDefaultsAndConfiguredSource() async throws {
        let mhzDef = SourceConfigDefaults.manhuazhan()
        XCTAssertEqual(mhzDef.id, "manhuazhan")
        XCTAssertEqual(mhzDef.name, "漫画栈")
        XCTAssertEqual(mhzDef.domain, "www.60ti.com")
        XCTAssertEqual(mhzDef.baseUrl, "https://www.60ti.com")
        XCTAssertEqual(mhzDef.referer, "https://www.60ti.com/")
        XCTAssertEqual(mhzDef.route("latest"), "/category{pagePath}")
        XCTAssertEqual(mhzDef.route("search"), "/search?key={keyword}")
        XCTAssertEqual(mhzDef.route("categoryIndex"), "/category/")
        XCTAssertEqual(mhzDef.route("detail"), "/comic_{comicId}.html")
        XCTAssertEqual(SourceConfigDefaults.defaultConfig(for: "manhuazhan")?.id, "manhuazhan")

        let bbyinDef = SourceConfigDefaults.bbyin()
        XCTAssertEqual(bbyinDef.id, "bbyin")
        XCTAssertEqual(bbyinDef.name, "比卡漫画")
        XCTAssertEqual(bbyinDef.domain, "bbyin.com")
        XCTAssertEqual(bbyinDef.baseUrl, "https://bbyin.com")
        XCTAssertEqual(bbyinDef.referer, "https://bbyin.com/")
        XCTAssertEqual(bbyinDef.route("latest"), "/category{pagePath}")
        XCTAssertEqual(bbyinDef.route("search"), "/search?key={keyword}")
        XCTAssertEqual(bbyinDef.route("categoryIndex"), "/category/")
        XCTAssertEqual(bbyinDef.route("detail"), "/comic_{comicId}.html")
        XCTAssertEqual(SourceConfigDefaults.defaultConfig(for: "bbyin")?.id, "bbyin")

        let custom = SourceConfigItem(
            id: "bbyin",
            name: "比卡镜像",
            domain: "mirror.bbyin.com",
            baseUrl: "https://mirror.bbyin.com",
            referer: "https://mirror.bbyin.com/",
            latestPath: "/category{pagePath}",
            searchPath: "/search?key={keyword}",
            categoryPath: "/category{pagePath}",
            detailPath: "/comic_{comicId}.html",
            enabled: true,
            routes: [
                "search": "/search?key={keyword}",
                "categoryIndex": "/category/",
                "detail": "/comic_{comicId}.html"
            ],
            filters: [:]
        )
        let transport = FiveUmTransport([
            "https://mirror.bbyin.com/search?key=%E5%A4%A9": cards
        ])
        let configured = FiveUmComicSource(config: custom, transport: transport)
        XCTAssertEqual(configured.id, "bbyin")
        XCTAssertEqual(configured.name, "比卡镜像")
        XCTAssertEqual(configured.referer, "https://mirror.bbyin.com/")
        let search = try await configured.search(keyword: "天", page: 1)
        XCTAssertEqual(search.count, 2)
        let reqs = await transport.requests
        XCTAssertEqual(reqs.first?.0, "https://mirror.bbyin.com/search?key=%E5%A4%A9")
        XCTAssertEqual(reqs.first?.1["Referer"], "https://mirror.bbyin.com/")
    }
}

private actor FiveUmTransport: HTTPTransport {
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

private struct FiveUmCancelledTransport: HTTPTransport {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse { throw CancellationError() }
}
