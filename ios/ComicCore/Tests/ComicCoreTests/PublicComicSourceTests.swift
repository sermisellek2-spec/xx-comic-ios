import Foundation
import XCTest
@testable import ComicCore

final class PublicComicSourceTests: XCTestCase {
    private final class Fixture: PublicComicSource, @unchecked Sendable {
        var pages: [String: String] = [:]
        var requests: [String] = []

        init(_ id: String) {
            super.init(config: PublicSourceRegistry.config(id))
        }

        override func request(_ url: String, method: String = "GET", body: String? = nil, referer: String? = nil, json: Bool = false) async throws -> PublicHTTPResponse {
            requests.append("\(method) \(url) \(body ?? "null")")
            guard let html = pages[url] else {
                throw NSError(domain: "PublicComicSourceTests", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unexpected request: \(url)"])
            }
            return PublicHTTPResponse(body: html, url: url, statusCode: 200)
        }
    }

    private func labels(_ group: SourceFilterGroup) -> [String] {
        group.options.map(\.label)
    }

    func testLaimanParsesDetailCoverAndAllBrowseTags() async throws {
        let s = Fixture("laiman")
        let detailUrl = "https://m.laimanhua.org/kanmanhua/617798"
        s.pages[detailUrl] = "<div class='dramaDetail_detailBox'><a class='image_imageBox dramaDetail_bookCover' href='[comic_link]'><img class='image_imageItem' alt='海贼王剧场版 红发歌姬' src='https://img1.baipiaoguai.org/static/upload3/book/id/508193/cover_1.jpg?v=1783717217'></a><h1 class='dramaDetail_bookName'>海贼王剧场版 红发歌姬</h1></div>"
        s.pages["https://m.laimanhua.org/"] = "<div class='home_container'><div class='home_browseBox'><a href='/category/tags/867' class='home_browseItem'>科幻</a><a href='/category/tags/872' class='home_browseItem'>恋爱</a><a href='/category/tags/873' class='home_browseItem'>恋爱</a><a href='/category/tags/888' class='home_browseItem'>武侠经典</a><a href='/category/tags/889' class='home_browseItem'>韩漫</a><a href='/category/tags/3597' class='home_browseItem'>搞笑喜剧</a></div></div>"
        let detail = try await s.detail(comicId: s.comicIdForUrl(detailUrl))
        XCTAssertTrue(detail.summary.coverUrl.contains("cover_1.jpg"))
        let group = try await s.filterGroups()[0]
        let options = group.options
        let expected = ["默认", "首页", "全部", "科幻", "后宫", "机甲", "都市", "恋爱生活", "恋爱", "恋爱", "其他", "推理悬疑", "魔法", "奇幻", "异世界", "滑稽搞笑", "重生", "励志", "浪漫", "逆袭", "脑洞", "日常", "热血机战", "魔法/奇幻", "武侠经典", "韩漫", "搞笑喜剧"]
        XCTAssertEqual(expected, labels(group))
        XCTAssertEqual("7", options[8].value)
        XCTAssertEqual("8", options[9].value)

        let card = "<div><a href='/kanmanhua/123'><img src='/cover.jpg' alt='分类结果'></a></div>"
        let first = "https://m.laimanhua.org/category/tags/867/page/1"
        let last = "https://m.laimanhua.org/category/tags/3597/page/1"
        s.pages[first] = card
        s.pages[last] = card
        let cat1 = try await s.category(region: "2", state: "all", page: 1)
        let cat2 = try await s.category(region: "/category/tags/3597", state: "all", page: 1)
        XCTAssertEqual(1, cat1.count)
        XCTAssertEqual(1, cat2.count)
        XCTAssertEqual(["GET \(first) null", "GET \(last) null"], Array(s.requests[2..<4]))
    }

    func testLmanhuaNationalComicsUsesItsPageHtmlRoute() async throws {
        let s = Fixture("lmanhua")
        let base = "https://lmanhua.com"
        let paths = ["/manga1", "/manga1/page1.html", "/manga1/page2.html"]
        for (i, path) in paths.enumerated() {
            s.pages[base + path] = "<div class='home-truyendecu'><a href='/novel\(7536 + i)/'><img src='/\(i + 1).jpg' alt='漫画\(i + 1)'></a></div>"
        }
        for page in 1...3 {
            let res = try await s.category(region: "4", state: "all", page: page)
            XCTAssertEqual(1, res.count)
        }
        XCTAssertEqual(["GET \(base)\(paths[0]) null", "GET \(base)\(paths[1]) null", "GET \(base)\(paths[2]) null"], s.requests)
    }

    func testTtkParsesCoverAndComposableCategoryFilters() async throws {
        let s = Fixture("ttk")
        let detailUrl = "https://www.ttkmh.com/manhua/419007"
        s.pages[detailUrl] = "<title>强占皇子殿下漫画-天天看漫画</title><div class='vod-info'><div class='pic'><img class='lazyload' src='https://img1.baipiaoguai.org/static/upload2/book/id/284345/cover_1.jpg' data-original='https://img1.baipiaoguai.org/static/upload2/book/id/284345/cover_1.jpg'></div><div class='info'><h3><a href='/manhua/419007'>强占皇子殿下</a></h3></div></div>"
        let detail = try await s.detail(comicId: s.comicIdForUrl(detailUrl))
        XCTAssertTrue(detail.summary.coverUrl.contains("cover_1.jpg"))

        let categoryIndex = "https://www.ttkmh.com/category/list/1"
        s.pages[categoryIndex] = "<div class='category-box'><dl><dt><span>标签</span></dt><dd><a href='/category/list/1'>全部</a><a href='/category/list/1/tags/867'>科幻</a></dd></dl><dl><dt><span>进度</span></dt><dd><a href='/category/list/1'>全部</a><a href='/category/list/1/finish/1'>连载</a><a href='/category/list/1/finish/2'>完结</a></dd></dl><dl><dt><span>排序</span></dt><dd><a href='/category/list/1/order/addtime'>最近更新</a><a href='/category/list/1/order/hits'>最多阅读</a></dd></dl></div>"
        let groups = try await s.filterGroups()
        XCTAssertEqual(["region", "tag", "finish", "order"], groups.map(\.key))
        XCTAssertEqual(["全部", "国产", "日本", "韩国", "欧美"], labels(groups[0]))
        XCTAssertEqual("科幻", groups[1].options[1].label)
        XCTAssertEqual(["全部", "连载", "完结"], labels(groups[2]))
        XCTAssertEqual(["最近更新", "最多阅读"], labels(groups[3]))

        let route = "https://www.ttkmh.com/category/list/2/tags/867/finish/1/order/hits/page/3"
        s.pages[route] = "<ul class='vod-list'><li><a href='/manhua/419007'><img src='/cover.jpg' alt='强占皇子殿下'></a></li></ul>"
        var filters: [String: String] = ["region": "2", "tag": "867", "finish": "1", "order": "hits"]
        let res1 = try await s.category(filters: filters, page: 3)
        XCTAssertEqual(1, res1.count)
        XCTAssertTrue(s.requests.last!.hasPrefix("GET \(route) "))

        let allRegionsRoute = "https://www.ttkmh.com/category/tags/867/order/addtime/page/1"
        s.pages[allRegionsRoute] = "<ul class='vod-list'><li><a href='/manhua/419007'><img src='/cover.jpg' alt='强占皇子殿下'></a></li></ul>"
        filters["region"] = "all"
        filters["finish"] = "all"
        filters["order"] = "addtime"
        let res2 = try await s.category(filters: filters, page: 1)
        XCTAssertEqual(1, res2.count)
        XCTAssertTrue(s.requests.last!.hasPrefix("GET \(allRegionsRoute) "))
    }

    func testRequestedSourcesDescribeDirectAccess() {
        for id in ["ttk", "laiman", "lmanhua"] {
            XCTAssertFalse(PublicSourceRegistry.networkHint(id).lowercased().contains("vpn"), id)
            XCTAssertTrue(PublicSourceRegistry.networkHint(id).contains("直连"), id)
        }
        XCTAssertTrue(PublicSourceRegistry.networkHint("favcomic").lowercased().contains("vpn"))
    }

    func testMh360ExposesEverySuppliedFilterWithoutFetchingTheWebsite() async throws {
        let s = Fixture("mh360")
        let groups = try await s.filterGroups()
        XCTAssertEqual(4, groups.count)
        let keys = ["type", "tag", "region", "finish"]
        let names = ["分类", "题材", "地区", "进度"]
        let segments = ["list", "tags", "city", "finish"]
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mh360-filters", withExtension: "html", subdirectory: "public-sources"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let rows = PublicHTMLDocument.parse(html).select(".cate-col")
        for i in 0..<4 {
            let group = groups[i]
            XCTAssertEqual(keys[i], group.key)
            XCTAssertEqual(names[i], group.label)
            let links = rows[i].select(".cate-list a")
            XCTAssertEqual(links.count, group.options.count)
            for j in 0..<links.count {
                XCTAssertEqual(links[j].text(), group.options[j].label)
                let href = links[j].attr("href")
                let expected: String
                if j == 0 {
                    expected = "all"
                } else {
                    let marker = "/\(segments[i])/"
                    let r = href.range(of: marker)!
                    expected = String(href[r.upperBound...])
                }
                XCTAssertEqual(expected, group.options[j].value)
            }
        }
        XCTAssertTrue(s.requests.isEmpty)
    }

    func testMh360UsesSeparateSearchPageRoutesAndStopsOnRepeatedResults() async throws {
        let s = Fixture("mh360")
        let base = "https://www.360mh.cc"
        let first = base + "/index.php/search?key=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9"
        let second = base + "/index.php/search/%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9/2"
        let card = "<div class='comic-list-item'><a href='/index.php/comic/doupocangqiong'><img src='/cover.jpg' alt='斗破苍穹'></a></div>"
        s.pages[first] = card
        s.pages[second] = card
        XCTAssertTrue(s.supportsSearch)
        let p1 = try await s.search(keyword: "斗破苍穹", page: 1)
        XCTAssertEqual("斗破苍穹", p1[0].title)
        let p2 = try await s.search(keyword: "斗破苍穹", page: 2)
        XCTAssertTrue(p2.isEmpty)
        XCTAssertEqual(["GET \(first) null", "GET \(second) null"], s.requests)
    }

    func testMh360SearchReturnsNewResultsOnTheSecondPage() async throws {
        let s = Fixture("mh360")
        let base = "https://www.360mh.cc"
        s.pages[base + "/index.php/search?key=%E6%96%97"] = "<div class='common-comic-item'><a href='/index.php/comic/first'><img src='/1.jpg' alt='斗破苍穹'></a></div>"
        s.pages[base + "/index.php/search/%E6%96%97/2"] = "<div class='comic-list-item'><a href='/index.php/comic/second'><img src='/2.jpg' alt='北斗之拳'></a></div>"
        let p1 = try await s.search(keyword: "斗", page: 1)
        let p2 = try await s.search(keyword: "斗", page: 2)
        XCTAssertEqual("mh360:/index.php/comic/first", p1[0].comicId)
        XCTAssertEqual("mh360:/index.php/comic/second", p2[0].comicId)
    }

    func testMh360FetchesActualCategoryPagesAndCombinesAllFourFilters() async throws {
        let s = Fixture("mh360")
        let base = "https://www.360mh.cc"
        let routes = ["/index.php/category", "/index.php/category/page/2", "/index.php/category/list/1/tags/6/city/42/finish/1/page/3", "/index.php/category/tags/76/city/45/finish/2"]
        for (i, route) in routes.enumerated() {
            s.pages[base + route] = "<div class='comic-item'><a href='/index.php/comic/book\(i)'><img src='/cover.jpg' alt='漫画\(i)'></a></div>"
        }
        let r0 = try await s.latest(page: 1)
        XCTAssertEqual("mh360:/index.php/comic/book0", r0[0].comicId)
        let r1 = try await s.category(filters: [:], page: 2)
        XCTAssertEqual("mh360:/index.php/comic/book1", r1[0].comicId)
        var filters: [String: String] = ["type": "1", "tag": "6", "region": "42", "finish": "1"]
        let r2 = try await s.category(filters: filters, page: 3)
        XCTAssertEqual("mh360:/index.php/comic/book2", r2[0].comicId)
        filters = ["type": "all", "tag": "76", "region": "45", "finish": "2"]
        let r3 = try await s.category(filters: filters, page: 1)
        XCTAssertEqual("mh360:/index.php/comic/book3", r3[0].comicId)
        XCTAssertEqual(routes.count, s.requests.count)
    }

    func testMh360MobileDetailExcludesItsCatalogAndRecommendedComics() async throws {
        let s = Fixture("mh360")
        let url = "https://www.360mh.cc/index.php/comic/yirenzhixia"
        s.pages[url] = "<h1 class='comic-name'>一人之下</h1><div class='box-back' style=\"background-image: url('/cover.jpg')\"></div>"
            + "<div class='detail-content'><div class='detail-intro'><span class='comic-intro'>完整漫画简介。</span><div class='author-info'>作者公告</div></div>"
            + "<div class='comic-recommend'><div class='cover'><img src='/wrong-cover.jpg'></div>推荐作品</div>"
            + "<div class='catalog-box'><ul><li class='chapter-item'><a href='/index.php/chapter/1'>第1话</a></li><li class='chapter-item'><a href='/index.php/chapter/2'>第2话</a></li></ul></div></div>"
        let detail = try await s.detail(comicId: s.comicIdForUrl(url))
        XCTAssertEqual("完整漫画简介。", detail.description)
        XCTAssertEqual("https://www.360mh.cc/cover.jpg", PublicSourceImages.strip(detail.summary.coverUrl))
        XCTAssertEqual("一人之下", detail.summary.title)
        XCTAssertTrue(detail.chapters.isEmpty)
        let chs = try await s.chapters(comicId: s.comicIdForUrl(url))
        XCTAssertEqual(2, chs.count)
    }

    func testMh360DesktopDetailPrefersFullIntroAndOwnCover() async throws {
        let s = Fixture("mh360")
        let url = "https://www.360mh.cc/index.php/comic/yirenzhixia"
        s.pages[url] = "<title>一人之下 - 360漫画</title><div class='de-info__cover'><img src='/own-cover.jpg'></div><p class='comic-title'>一人之下</p>"
            + "<div class='comic-intro'><p class='intro'>简介截断...</p><p class='show'>展开</p><p class='intro-total'>完整漫画简介。</p></div>"
            + "<li class='j-chapter-item'><a href='/index.php/chapter/1'>第1话</a></li>"
        let detail = try await s.detail(comicId: s.comicIdForUrl(url))
        XCTAssertEqual("完整漫画简介。", detail.description)
        XCTAssertEqual("一人之下", detail.summary.title)
        XCTAssertEqual("https://www.360mh.cc/own-cover.jpg", PublicSourceImages.strip(detail.summary.coverUrl))
        let chs = try await s.chapters(comicId: s.comicIdForUrl(url))
        XCTAssertEqual(1, chs.count)
    }

    func testFavcomicExposesCompleteFiltersAndBuildsCategoryRoutes() async throws {
        let s = Fixture("favcomic")
        let groups = try await s.filterGroups()
        XCTAssertEqual(["type", "origin", "finished", "tag", "order"], groups.map(\.key))
        XCTAssertEqual(["全部", "少男漫画", "少女漫画", "绅士漫画", "图库"], labels(groups[0]))
        XCTAssertEqual(["全部", "日本", "韩国", "大陆及港台", "其它"], labels(groups[1]))
        XCTAssertEqual(["全部", "连载", "完结"], labels(groups[2]))
        XCTAssertEqual(["更新时间", "人气推荐"], labels(groups[4]))
        XCTAssertTrue(labels(groups[3]).contains("少男 · 奇幻"))
        XCTAssertTrue(labels(s.filterGroupsForType("girl")[3]).contains("ABO"))

        let card = "<div class='comic_li'><a href='/comic/detail/1'><img src='/cover.jpg' alt='喜漫分类'></a></div>"
        let route = "https://www.favcomic.com/boy?origin=2&finished=1&tag=1&sort=1&page=2"
        s.pages[route] = card
        let filters: [String: String] = ["type": "boy", "origin": "2", "finished": "1", "tag": "boy:1", "order": "popular"]
        let res = try await s.category(filters: filters, page: 2)
        XCTAssertEqual(1, res.count)
        XCTAssertTrue(s.requests[0].hasPrefix("GET \(route) "))
    }

    func testFavcomicRequestsAlwaysForceFreeQuery() {
        XCTAssertEqual("https://www.favcomic.com/boy?page=2&free=1", PublicComicSource.favFreeUrl("https://www.favcomic.com/boy?page=2"))
        XCTAssertEqual("https://www.favcomic.com/boy?page=2&free=1", PublicComicSource.favFreeUrl("https://www.favcomic.com/boy?free=0&page=2"))
    }

    func testSameChapterPagesMergedButNextChapterNeverFollowed() async throws {
        let s = Fixture("waiwai")
        let base = "https://m.waiwaimhx.com/chapter/464/25798"
        s.pages[base + ".html"] = "<div id=cp_img><img data-src='https://cdn.test/1.jpg'></div><a href='25798_2.html'>下一页</a>"
        s.pages[base + "_2.html"] = "<div id=cp_img><img data-src='https://cdn.test/2.jpg'></div><a href='25799.html'>下一章</a><a href='/book/464/'>目录</a>"
        let page = try await s.chapter(url: base + ".html")
        XCTAssertEqual(2, page.imageUrls.count)
        XCTAssertEqual("", page.nextPageUrl)
        XCTAssertEqual(2, s.requests.count)
        XCTAssertEqual(base + ".html", PublicSourceImages.referer(page.imageUrls[1]))
        XCTAssertEqual(base + ".html", page.chapterId)
    }

    func testEmpireCollectsAllCatalogPagesAndRejectsRecommendations() async throws {
        let s = Fixture("lele")
        let base = "https://www.hmwu.cc/comic6431/"
        s.pages[base] = "<div class=book_list><a href='chapter0.html'>第1话</a><a href='?p=2'>下一页</a><a href='/comic999/chapter2.html'>推荐</a></div>"
        s.pages[base + "?p=2"] = "<div class=book_list><a href='chapter1.html'>第2话</a><a href='chapter2.html'>番外</a></div>"
        let chapters = try await s.chapters(comicId: s.comicIdForUrl(base))
        XCTAssertEqual(3, chapters.count)
        XCTAssertEqual("番外", chapters[2].title)
    }

    func testRepeatedCatalogPageFailsInsteadOfClaimingCompleteness() async throws {
        let s = Fixture("lmanhua")
        let url = "https://lmanhua.com/novel7536/"
        s.pages[url] = "<a href='chapter0.html'>第1卷</a><a href='?p=2'>2</a>"
        s.pages[url + "?p=2"] = "<a href='chapter0.html'>第1卷</a>"
        do {
            _ = try await s.chapters(comicId: s.comicIdForUrl(url))
            XCTFail("Expected repeated catalog error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("重复"))
        }
    }

    func testFullWdApiUsedInsteadOfTruncatedHtmlAndSourceIdentityPreserved() async throws {
        let s = Fixture("wmanhua")
        let base = "https://www.wmanhua.com"
        s.pages[base + "/comic/5971"] = "{code:0,data:{chapters:[{id:'9',contentId:'5971',chapterName:'第3话'},{id:'8',contentId:'5971',chapterName:'番外'},{id:'7',contentId:'5971',chapterName:'第1卷'}]}}"
        let chapters = try await s.chapters(comicId: "wmanhua:/comic/5971.html")
        XCTAssertEqual(3, chapters.count)
        XCTAssertEqual("第1卷", chapters[0].title)
        XCTAssertEqual("番外", chapters[1].title)
        XCTAssertTrue(s.requests[0].hasPrefix("POST "))
        XCTAssertTrue(s.requests[0].hasSuffix("form=form"))
        let cards = try s.cards("<div class=manga-card><a href='/comic/5971.html'><img src='/cover.jpg' alt='海贼王'></a></div>", base)
        XCTAssertEqual("wmanhua:/comic/5971.html", cards[0].comicId)
        XCTAssertEqual("wmanhua", cards[0].sourceId)
    }

    func testFreeCatalogDoesNotExposeMemberOrPaidChapters() async throws {
        let s = Fixture("comic51")
        let base = "https://www.favcomic.xyz/comic/detail/100"
        s.pages[base] = "<a class=item_box href='/comic/chapter/1'><span class=title>第1话</span><span>￥0</span></a><a class=item_box href='/comic/chapter/2'>第2话 会员专享</a><a class=item_box href='/comic/chapter/3'>第3话 ￥0.8</a><a class=item_box href='/comic/chapter/4'>第4话 ￥10</a>"
        let list = try await s.chapters(comicId: s.comicIdForUrl(base))
        XCTAssertEqual(1, list.count)
        XCTAssertEqual("第1话", list[0].title)
    }

    func testFavCatalogReadsJsonLdHasPartWhenHtmlListIsMissing() async throws {
        let s = Fixture("favcomic")
        let base = "https://www.favcomic.com/comic/detail/1304073462710874112"
        s.pages[base] = "<script type='application/ld+json'>{\"@type\":\"Book\",\"numberOfChapters\":1,\"offers\":{\"price\":\"0\"},\"hasPart\":[{\"@type\":\"Book\",\"name\":\"全集（19P）\",\"url\":\"https://www.favcomic.com/comic/chapter/1304096430606544896\"}]}</script>"
        let list = try await s.chapters(comicId: s.comicIdForUrl(base))
        XCTAssertEqual(1, list.count)
        XCTAssertEqual("全集（19P）", list[0].title)
        XCTAssertEqual("https://www.favcomic.com/comic/chapter/1304096430606544896", list[0].url)
    }

    func testFavCatalogKeepsMemberChaptersAndRejectsPricedChapters() async throws {
        let s = Fixture("favcomic")
        let base = "https://www.favcomic.com/comic/detail/100"
        s.pages[base] = "<a class=item_box href='/comic/chapter/1'><span class=title>第1话</span>￥0</a><a class=item_box href='/comic/chapter/2'><span class=title>第2话</span>会员专享</a><a class=item_box href='/comic/chapter/3'>第3话 ￥0.8</a><a class=item_box href='/comic/chapter/4'>第4话 ￥10</a>"
        let list = try await s.chapters(comicId: s.comicIdForUrl(base))
        XCTAssertEqual(2, list.count)
        XCTAssertEqual("第2话", list[1].title)
        XCTAssertEqual("https://www.favcomic.com/comic/chapter/2", list[1].url)
    }

    func testFavJsonLdCatalogPreservesOrderAndRejectsPaidOrForeignEntries() async throws {
        let s = Fixture("favcomic")
        let base = "https://www.favcomic.com/comic/detail/100"
        s.pages[base] = "<script type='application/ld+json'>broken</script><script type='application/ld+json'>{\"@type\":\"BreadcrumbList\"}</script>"
            + "<script type='application/ld+json'>{\"@graph\":[{\"@type\":\"Book\",\"url\":\"https://www.favcomic.com/comic/detail/999\",\"hasPart\":[{\"name\":\"推荐章节\",\"url\":\"/comic/chapter/99\"}]},{\"@type\":\"Book\",\"url\":\"" + base + "\",\"hasPart\":["
            + "{\"name\":\"上篇\",\"url\":\"/comic/chapter/2\"},{\"name\":\"下篇\",\"url\":\"/comic/chapter/1\",\"offers\":{\"price\":\"0.00\"}},"
            + "{\"name\":\"付费\",\"url\":\"/comic/chapter/3\"},{\"name\":\"付费 JSON\",\"url\":\"/comic/chapter/4\",\"offers\":{\"price\":\"0.8\"}},"
            + "{\"name\":\"外站\",\"url\":\"https://other.test/comic/chapter/5\"},{\"name\":\"无效链接\",\"url\":\"/other/comic/chapter/6\"},{\"name\":\"重复\",\"url\":\"/comic/chapter/2\"}]}]}</script>"
            + "<a class=item_box href='/comic/chapter/1'><span class=title>下篇</span>￥0</a><a class=item_box href='/comic/chapter/2'><span class=title>上篇</span>会员专享</a><a class=item_box href='/comic/chapter/3'>付费 ￥0.8</a>"
        let list = try await s.chapters(comicId: s.comicIdForUrl(base))
        XCTAssertEqual(2, list.count)
        XCTAssertEqual("上篇", list[0].title)
        XCTAssertEqual("下篇", list[1].title)
        XCTAssertEqual(0, list[0].chapterSlot)
        XCTAssertEqual(1, list[1].chapterSlot)
    }

    func testSignaturesRefreshWithoutChangingCacheIdentity() async throws {
        let s = Fixture("tuku")
        let chapter = "https://www.tuku.cc/chapter1/"
        s.pages[chapter] = "<div class=container><img data-original='https://cdn.test/1.jpg?key=old'></div>"
        let old = try await s.chapter(url: chapter).imageUrls[0]
        s.pages[chapter] = "<div class=container><img data-original='https://cdn.test/1.jpg?key=new'></div>"
        let resolved = try await s.resolveImageUrl(old, force: true)
        XCTAssertEqual("https://cdn.test/1.jpg?key=new", resolved)
        let fresh = try await s.chapter(url: chapter).imageUrls[0]
        XCTAssertEqual(PublicSourceImages.cacheIdentity(old), PublicSourceImages.cacheIdentity(fresh))
        XCTAssertNotEqual(PublicSourceImages.cacheIdentity(old), PublicSourceImages.cacheIdentity(PublicSourceImages.tag("https://cdn.test/1.jpg", "comic51", chapter, 0)))
    }

    func testAesListAndImageBytesAreDifferentFormats() throws {
        let iv = Data(repeating: 7, count: 16)
        let payload = Data("{\"images\":[\"/1.jpg\",\"/2.jpg\"]}".utf8)
        let encryptedBody = try SourceAES.encrypt(payload, key: Data("9S8$vJnU2ANeSRoF".utf8), iv: iv)
        var encrypted = Data()
        encrypted.append(iv)
        encrypted.append(encryptedBody)
        let encoded = encrypted.base64EncodedString()
        let urls = try PublicSourceImages.extract("var params='\(encoded)';", "https://www.ycymh.com/chapter/1", try PublicSourceRegistry.profile("ycy"))
        XCTAssertEqual(["https://img1.baipiaoguai.org/1.jpg", "https://img1.baipiaoguai.org/2.jpg"], urls)

        let image = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let cipherBody = try SourceAES.encrypt(image, key: try PublicSourceImages.b64("NlgrYjYuRT5ic1hifSs9Tg=="), iv: iv)
        var cipher = Data()
        cipher.append(iv)
        cipher.append(cipherBody)
        let tagged = PublicSourceImages.tag("https://shared.test/a.webp", "comic51", "https://www.favcomic.xyz/comic/chapter/1", 0)
        XCTAssertEqual(image, try PublicSourceImages.decode(cipher, tagged: tagged))
        let other = PublicSourceImages.tag("https://shared.test/a.webp", "tuku", "https://www.tuku.cc/chapter1/", 0)
        XCTAssertEqual(cipher, try PublicSourceImages.decode(cipher, tagged: other))
    }

    func testDm5SearchUsesConsistentApiAndCorrectPage() async throws {
        let s = Fixture("dm5")
        s.pages["https://m.dm5.com/pagerdata.ashx"] = "[{Title:'海贼王',Url:'/manhua-haizeiwang/',Pic:'https://cdn.test/a.jpg'}]"
        let res = try await s.search(keyword: "海贼王", page: 2)
        XCTAssertEqual(1, res.count)
        XCTAssertTrue(s.requests[0].contains("pageindex=2"))
        XCTAssertTrue(s.requests[0].contains("t=7"))
    }

    func testFiniteListsEndAndUnavailableSearchNeverRequestsHomepage() async throws {
        let s = Fixture("sisi")
        s.pages["https://m.sisimanhua.com/new/"] = "<li><a href='/manhua/abc/'><img src='/x.jpg' alt='示例'></a></li>"
        let p1 = try await s.latest(page: 1)
        let p2 = try await s.latest(page: 2)
        XCTAssertEqual(1, p1.count)
        XCTAssertTrue(p2.isEmpty)
        let m = Fixture("mh250")
        XCTAssertFalse(m.supportsSearch)
        let sp = try await m.search(keyword: "任何关键词", page: 1)
        XCTAssertTrue(sp.isEmpty)
        XCTAssertTrue(m.requests.isEmpty)
    }

    func testRegistryConfigsRoundTripAndIdsAreUnique() {
        XCTAssertEqual(29, PublicSourceRegistry.ids().count)
        XCTAssertFalse(PublicSourceRegistry.contains("haoman"))
        XCTAssertFalse(PublicSourceRegistry.contains("mengjie"))
        XCTAssertFalse(PublicSourceRegistry.contains("mumu"))
        for (_, c) in PublicSourceRegistry.defaults() {
            let disabled = c.withEnabled(false)
            XCTAssertFalse(disabled.enabled)
            XCTAssertEqual(c.id, disabled.id)
            XCTAssertEqual(c.id, PublicSourceRegistry.create(disabled).id)
        }
    }

    func testDAndWExposeSharedRegionAndTagFiltersAndBuildRoutes() async throws {
        for id in ["dmanhua", "wmanhua"] {
            let s = Fixture(id)
            let base = PublicSourceRegistry.config(id).baseUrl
            let groups = try await s.filterGroups()
            XCTAssertEqual(["region", "tag"], groups.map(\.key))
            XCTAssertEqual("全部", groups[0].options[0].label)
            XCTAssertEqual("日本漫画", groups[0].options[1].label)
            XCTAssertTrue(groups[1].options.count > 80)
            XCTAssertEqual("爱情", groups[1].options[1].label)
            let route = base + "/sort?category=2&tag=14&page=3"
            s.pages[route] = "<div class='card-content'><a href='/comic/1.html'><img src='/cover.jpg' alt='测试'></a></div>"
            let filters: [String: String] = ["region": "2", "tag": "14"]
            let res = try await s.category(filters: filters, page: 3)
            XCTAssertEqual(1, res.count)
            XCTAssertTrue(s.requests[0].hasPrefix("GET \(route) "))
        }
    }

    func testCiyuanExposesCompleteTagListAndBuildsTagPages() async throws {
        let s = Fixture("ciyuan")
        let groups = try await s.filterGroups()
        XCTAssertEqual(1, groups.count)
        XCTAssertEqual("tag", groups[0].key)
        XCTAssertTrue(groups[0].options.count > 590)
        XCTAssertEqual("奇幻", groups[0].options[1].label)
        XCTAssertEqual("3221", groups[0].options.last?.value)
        let route = "https://ciyuanman.com/category/tags/3221/page/2"
        s.pages[route] = "<div class='img-list'><li><a href='/kan/500903'><img src='/cover.jpg' alt='测试'></a></li></div>"
        let res = try await s.category(filters: ["tag": "3221"], page: 2)
        XCTAssertEqual(1, res.count)
        XCTAssertTrue(s.requests[0].hasPrefix("GET \(route) "))
    }

    func testDumanwuExposesProgressTagRegionAndDetailCover() async throws {
        let s = Fixture("dumanwu")
        let groups = try await s.filterGroups()
        XCTAssertEqual(["finish", "tag", "region"], groups.map(\.key))
        XCTAssertEqual(["全部", "连载", "完结"], labels(groups[0]))
        XCTAssertTrue(groups[1].options.count > 100)
        XCTAssertEqual(["全部", "国产漫画", "日本漫画", "韩国漫画", "欧美漫画"], labels(groups[2]))
        let detail = "https://m.dumanwu.org/comic/gkx7ZZyw2E"
        s.pages[detail] = "<div class='detailTop'><div class='content'><img class='cover' src='https://cdn.test/cover.jpg' alt='大主宰'><p class='title'>大主宰</p></div></div><div class='detailContent'><p>简介</p></div>"
        let parsed = try await s.detail(comicId: s.comicIdForUrl(detail))
        XCTAssertEqual("https://cdn.test/cover.jpg", PublicSourceImages.strip(parsed.summary.coverUrl))
        XCTAssertEqual("大主宰", parsed.summary.title)
    }

    func testDuplicateImageClassAttributesStillYieldReaderImages() throws {
        let html = "<div class=font_max><img class='comic_img lazy' class='responsive-image' data-original='https://cdn.test/1.jpg'></div><img data-original='https://ads.test/ad.jpg'>"
        let urls = try PublicSourceImages.extract(html, "https://www.hmwu.cc/comic1/chapter0.html", try PublicSourceRegistry.profile("lele"))
        XCTAssertEqual(["https://cdn.test/1.jpg"], urls)
    }

    func testCursorPaginationCarriesServerToken() async throws {
        let s = Fixture("dogemanga")
        let base = "https://dogemanga.com"
        s.pages[base + "/?s=1"] = "<div class=col-12><a href='/m/first'><img alt='第一本' src='/1.jpg'></a></div><a href='/?p=cursorXYZ&s=1'>下一頁</a>"
        s.pages[base + "/?p=cursorXYZ&s=1"] = "<div class=col-12><a href='/m/second'><img alt='第二本' src='/2.jpg'></a></div>"
        let res = try await s.latest(page: 2)
        XCTAssertEqual("dogemanga:/m/second", res[0].comicId)
        XCTAssertEqual(2, s.requests.count)
    }

    func testLargePackedStringDoesNotRecurseOnEachCharacter() throws {
        let padding = String(repeating: "x", count: 50000)
        let html = "}(\"var newImgs=['https://cdn.test/1.jpg'];/*\(padding)*/\",2,1,'unused'.split('|'))"
        let urls = try PublicSourceImages.extract(html, "https://m.dm5.com/m1/", try PublicSourceRegistry.profile("dm5"))
        XCTAssertEqual(["https://cdn.test/1.jpg"], urls)
    }

    func testSearchEndUsesActualNextLinkAndCmsSentinel() async throws {
        let y = Fixture("ycy")
        let url = "https://www.ycymh.com/search/%E9%94%99%E6%92%A9/1"
        y.pages[url] = "<div class=vbox><a href='/comic/1'><img alt='错撩' src='/1.jpg'></a></div><a href='/search/错撩'>下一页</a>"
        let y1 = try await y.search(keyword: "错撩", page: 1)
        let y2 = try await y.search(keyword: "错撩", page: 2)
        XCTAssertEqual(1, y1.count)
        XCTAssertTrue(y2.isEmpty)
        XCTAssertEqual(1, y.requests.count)
        let s = Fixture("sisi")
        s.pages["https://m.sisimanhua.com/statics/qingtiancms.ashx"] = "{err!}"
        let s2 = try await s.search(keyword: "关键词", page: 2)
        XCTAssertTrue(s2.isEmpty)
    }

    func testUnclosedParagraphAndStrayInlineCloseDoNotBreakCatalogContainer() throws {
        let html = """
        <p>未闭合段落
        <div class="chapter-wrap">
            <span>简介</p></span>
            <a href="https://www.tuku.cc/chapter1/">第1话</a>
            <a href="https://www.tuku.cc/chapter2/">第2话</a>
        </div>
        """
        let doc = PublicHTMLDocument.parse(html, baseUri: "https://www.tuku.cc/manga-1/")
        let links = doc.select(".chapter-wrap a")
        XCTAssertEqual(2, links.count)
    }

    func testLivePublicSourcesProbeIfEnabled() async throws {
        guard ProcessInfo.processInfo.environment["XX_PUBLIC_LIVE_PROBE"] == "1" else { return }
        let words = [
            "海贼王", "海贼王", "海贼王", "如出一辙", "海賊王", "情绪病", "衣冠", "美丽",
            "海贼王", "错撩", "", "", "", "", "坂田", "",
            "神祇", "", "", "", "海贼王", "海贼王", "Not Sober", "常葉",
            "人人", "", "", "", "海贼王", "", "海贼王剧场版", "海贼王"
        ]
        let onlyEnv = ProcessInfo.processInfo.environment["XX_PUBLIC_ONLY"]
        let selectedIds: [String]
        if let onlyEnv, !onlyEnv.isEmpty {
            let set = Set(onlyEnv.components(separatedBy: ","))
            selectedIds = PublicSourceRegistry.ids().filter { set.contains($0) }
        } else {
            selectedIds = PublicSourceRegistry.ids()
        }

        let transport = URLSessionHTTPTransport(timeoutInterval: 20)
        var allResultsById: [String: [String: Any]] = [:]

        @Sendable func probeOne(_ id: String) async -> [String: Any] {
            let config = PublicSourceRegistry.config(id)
            guard let profile = try? PublicSourceRegistry.profile(id) else {
                return ["id": id, "error": "missing profile"]
            }
            let source = PublicComicSource(config: config, transport: transport)
            var res: [String: Any] = [
                "id": id,
                "name": source.name,
                "base": config.baseUrl,
                "defaultEnabled": config.enabled,
                "supportsSearch": source.supportsSearch,
                "networkHint": PublicSourceRegistry.networkHint(id),
                "capabilityHint": PublicSourceRegistry.capabilityHint(id)
            ]

            var first: [ComicSummary] = []
            do {
                first = try await source.latest(page: 1)
                res["listCount"] = first.count
                if let f0 = first.first {
                    res["firstComicId"] = f0.comicId
                    res["firstTitle"] = f0.title
                }
            } catch {
                res["listError"] = error.localizedDescription
            }

            if !first.isEmpty {
                do {
                    let second = try await source.latest(page: 2)
                    let ids = Set(first.map(\.comicId))
                    let novel = second.filter { !ids.contains($0.comicId) }.count
                    res["page2Count"] = second.count
                    res["page2New"] = novel
                } catch {
                    res["page2Error"] = error.localizedDescription
                }
            }

            do {
                let groups = try await source.filterGroups()
                res["filterGroupCount"] = groups.count
                if let g0 = groups.first, !g0.options.isEmpty {
                    let optIdx = min(profile.family == "dm5" ? 6 : 2, g0.options.count - 1)
                    let opt = g0.options[optIdx]
                    let filtered = try await source.category(filters: [g0.key: opt.value], page: 1)
                    res["filterLabel"] = opt.label
                    res["filterValue"] = opt.value
                    res["filterCount"] = filtered.count
                }
            } catch {
                res["filterError"] = error.localizedDescription
            }

            if let f0 = first.first, !f0.coverUrl.isEmpty {
                do {
                    let cover = f0.coverUrl
                    let stripped = PublicSourceImages.strip(cover)
                    res["coverUrl"] = stripped
                    if let url = PublicSourceImages.parseLenientURL(stripped) {
                        let resp = try await transport.get(url, headers: [
                            "User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36",
                            "Referer": PublicSourceImages.referer(cover, fallback: source.referer),
                            "Accept": "image/webp,image/apng,image/*,*/*;q=0.8"
                        ])
                        if resp.statusCode == 200 {
                            let decoded = try PublicSourceImages.decode(cover, resp.data)
                            res["coverBytes"] = decoded.count
                            res["coverValid"] = ImageValidator.isValidImage(data: decoded)
                            res["coverSha256"] = DownloadModels.sha256Hex(decoded)
                        } else {
                            res["coverError"] = "HTTP \(resp.statusCode)"
                        }
                    }
                } catch {
                    res["coverError"] = error.localizedDescription
                }
            }

            if source.supportsSearch {
                let idx = max(0, min(words.count - 1, profile.auditIndex - 1))
                let word = words[idx].isEmpty ? "海贼王" : words[idx]
                res["keyword"] = word
                do {
                    let found = try await source.search(keyword: word, page: 1)
                    let normWord = word.replacingOccurrences(of: "贼", with: "賊")
                    let match = found.contains { $0.title.replacingOccurrences(of: "贼", with: "賊").contains(normWord) }
                    res["searchCount"] = found.count
                    res["searchMatch"] = match
                    res["searchTitles"] = Array(found.prefix(3).map(\.title))
                    if !found.isEmpty {
                        do {
                            let next = try await source.search(keyword: word, page: 2)
                            let prevIds = Set(found.map(\.comicId))
                            let novel = next.filter { !prevIds.contains($0.comicId) }.count
                            res["searchPage2Count"] = next.count
                            res["searchPage2New"] = novel
                        } catch {
                            res["searchPage2Error"] = error.localizedDescription
                        }
                    }
                } catch {
                    res["searchError"] = error.localizedDescription
                }
            }

            let sampleComicId = source.comicIdForUrl(profile.sampleDetail)
            res["sampleDetailUrl"] = profile.sampleDetail
            var resolvedChapters: [Chapter] = []
            do {
                let detail = try await source.detail(comicId: sampleComicId)
                res["detailTitle"] = detail.summary.title
                let chs = try await source.chapters(comicId: sampleComicId)
                resolvedChapters = chs
                res["chapterCount"] = chs.count
                res["chapterFirst"] = Array(chs.prefix(3).map(\.title))
            } catch {
                res["detailError"] = error.localizedDescription
                if let fallbackId = first.first?.comicId {
                    do {
                        let detail = try await source.detail(comicId: fallbackId)
                        res["fallbackDetailTitle"] = detail.summary.title
                        let chs = try await source.chapters(comicId: fallbackId)
                        resolvedChapters = chs
                        res["fallbackChapterCount"] = chs.count
                        res["fallbackChapterFirst"] = Array(chs.prefix(3).map(\.title))
                    } catch {
                        res["fallbackDetailError"] = error.localizedDescription
                    }
                }
            }

            let chapterToTest = !profile.sampleChapter.isEmpty ? profile.sampleChapter : (resolvedChapters.first?.url ?? "")
            res["sampleChapterUrl"] = chapterToTest
            do {
                var page: ChapterPage
                do {
                    page = try await source.chapter(url: chapterToTest)
                } catch {
                    if let firstChUrl = resolvedChapters.first?.url, firstChUrl != chapterToTest {
                        res["sampleChapterError"] = error.localizedDescription
                        res["fallbackChapterUrl"] = firstChUrl
                        page = try await source.chapter(url: firstChUrl)
                    } else {
                        throw error
                    }
                }
                res["imageCount"] = page.imageUrls.count
                var checks: [[String: Any]] = []
                let count = page.imageUrls.count
                let positions = Array(Set([0, count / 2, max(0, count - 1)])).sorted()
                for pos in positions where pos < count {
                    var check: [String: Any] = ["page": pos + 1]
                    do {
                        let tagged = page.imageUrls[pos]
                        let resolved = try await source.resolveImageUrl(tagged, force: false)
                        let stripped = PublicSourceImages.strip(resolved)
                        check["url"] = stripped
                        if let imgUrl = PublicSourceImages.parseLenientURL(stripped) {
                            let resp = try await transport.get(imgUrl, headers: [
                                "User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36",
                                "Referer": PublicSourceImages.referer(tagged, fallback: source.referer),
                                "Accept": "image/webp,image/apng,image/*,*/*;q=0.8"
                            ])
                            check["status"] = resp.statusCode
                            if resp.statusCode == 200 {
                                let decoded = try PublicSourceImages.decode(tagged, resp.data)
                                check["bytes"] = decoded.count
                                check["valid"] = ImageValidator.isValidImage(data: decoded)
                                check["sha256"] = DownloadModels.sha256Hex(decoded)
                            }
                        }
                    } catch {
                        check["error"] = error.localizedDescription
                    }
                    checks.append(check)
                }
                res["images"] = checks
            } catch {
                res["readerError"] = error.localizedDescription
            }

            print("LIVE_PROBE \(id): list=\(res["listCount"] ?? -1) ch=\(res["chapterCount"] ?? res["fallbackChapterCount"] ?? -1) img=\(res["imageCount"] ?? -1)")
            return res
        }

        let batchSize = 6
        let outUrl = URL(fileURLWithPath: "/work/.live-probe-results.json")
        if let existingData = try? Data(contentsOf: outUrl),
           let existingArr = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
            for item in existingArr {
                if let itemId = item["id"] as? String {
                    allResultsById[itemId] = item
                }
            }
        }
        for start in stride(from: 0, to: selectedIds.count, by: batchSize) {
            let batch = Array(selectedIds[start..<min(start + batchSize, selectedIds.count)])
            await withTaskGroup(of: (String, [String: Any]).self) { group in
                for id in batch {
                    group.addTask {
                        let r = await probeOne(id)
                        return (id, r)
                    }
                }
                for await (id, r) in group {
                    allResultsById[id] = r
                }
            }
            let ordered = PublicSourceRegistry.ids().compactMap { allResultsById[$0] }
            let jsonData = try JSONSerialization.data(withJSONObject: ordered, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: outUrl)
        }
    }
}
