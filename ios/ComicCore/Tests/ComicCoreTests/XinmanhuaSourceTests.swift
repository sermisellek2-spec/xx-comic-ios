import XCTest
@testable import ComicCore

final class XinmanhuaSourceTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        var lastUrl: String = ""
        var lastMethod: String = ""
        var lastBody: String = ""

        func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
            lastUrl = url.absoluteString
            lastMethod = "GET"
            lastBody = ""
            let body: String
            if lastUrl.contains("/qualitywebs") {
                body = #"{"data":[{"type":"qualitywebs","id":"1","attributes":{"chapid":50,"url":"http://works.xinmanhua.net/273042737/1/w/1_a.jpg"}},{"type":"qualitywebs","id":"2","attributes":{"chapid":50,"url":"http://works.xinmanhua.net/273042737/1/w/2_b.jpg"}}]}"#
            } else if lastUrl.contains("/chapters") {
                body = #"{"data":[{"type":"chapters","id":"50","attributes":{"wid":"273042737","cidx":1,"title":"第1回","intro":"刀马与小七"}}]}"#
            } else if lastUrl.contains("/worksinfos/") {
                body = #"{"data":{"type":"worksinfos","id":"27","attributes":{"wid":"273042737","title":"镖人","author":"作者甲","intro":"故事简介","description":"详细介绍","logo_detail":"http://works.xinmanhua.net/cover.jpg","isfinish":0,"lastctitle":"第127回"}}}"#
            } else {
                body = #"{"data":[{"type":"worksinfos","id":"27","attributes":{"wid":"273042737","title":"镖人","logo":"http://works.xinmanhua.net/cover.jpg"}}]}"#
            }
            return HTTPResponse(data: Data(body.utf8), statusCode: 200)
        }

        func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
            lastUrl = url.absoluteString
            lastMethod = "POST"
            lastBody = String(data: body, encoding: .utf8) ?? ""
            let resp = #"{"data":[{"type":"worksinfos","id":"27","attributes":{"wid":"273042737","title":"镖人","author":"作者甲","intro":"故事简介","logo_detail":"http://works.xinmanhua.net/cover.jpg","lastctitle":"第127回"}}]}"#
            return HTTPResponse(data: Data(resp.utf8), statusCode: 200)
        }
    }

    func testSearchCategoryDetailChaptersAndQualityImagesAreParsed() async throws {
        let transport = FakeTransport()
        let source = XinmanhuaComicSource(config: SourceConfigDefaults.xinmanhua(enabled: true), transport: transport)
        let result = try await source.search(keyword: "镖人", page: 1)[0]
        XCTAssertEqual("xinmanhua:273042737", result.comicId)
        XCTAssertEqual("镖人", result.title)
        XCTAssertEqual("https://works.xinmanhua.net/cover.jpg", result.coverUrl)
        XCTAssertEqual("POST", transport.lastMethod)
        XCTAssertTrue(transport.lastBody.contains("keyword=%E9%95%96%E4%BA%BA&page=1"))

        _ = try await source.search(keyword: "人", page: 2)
        XCTAssertTrue(transport.lastUrl.hasSuffix("?page=2"))

        _ = try await source.category(filters: ["genre": "治愈"], page: 2)
        XCTAssertTrue(transport.lastUrl.contains("keyword=%E6%B2%BB%E6%84%88"))
        XCTAssertTrue(transport.lastUrl.hasSuffix("page=2"))

        let detail = try await source.detail(comicId: result.comicId)
        XCTAssertEqual("作者甲", detail.author)

        let chapters = try await source.chapters(comicId: result.comicId)
        XCTAssertEqual("50", chapters[0].chapterId)
        XCTAssertEqual("第1回 刀马与小七", chapters[0].title)

        let page = try await source.chapter(url: chapters[0].url)
        XCTAssertEqual(2, page.imageUrls.count)
        XCTAssertEqual("https://works.xinmanhua.net/273042737/1/w/1_a.jpg", page.imageUrls[0])
    }

    // MARK: - FourSourceRegressionTest (1:1 port)

    func testWrappedAndPlainJpegRemainReadable() throws {
        let jpeg = Data([0xff, 0xd8, 0xff, 42])
        var wrapped = Data(repeating: 0, count: 84)
        let magic = Data("http://www.xinmanhua.net".utf8)
        wrapped.replaceSubrange(0..<magic.count, with: magic)
        wrapped.replaceSubrange(80..<84, with: jpeg)

        for input in [jpeg, wrapped] {
            let decoded = try XinmanhuaImageDecoder.decode(input)
            XCTAssertEqual(jpeg, decoded)
        }
        XCTAssertTrue(XinmanhuaImageDecoder.usesImageHost("https://works.xinmanhua.net/a.jpg"))
        XCTAssertFalse(XinmanhuaImageDecoder.usesImageHost("https://works.xinmanhua.net.other.net/a.jpg"))
        XCTAssertThrowsError(try XinmanhuaImageDecoder.decode(magic))
    }

    func testDingBuildsActualPagesAndExcludesAds() throws {
        let html = "<img src='https://ads.invalid/ad.gif'><script>var num=eval(\"3\");var pasd='https://image1.dingmanhua.com/mh/book/chapter/';img.src=pasd+i+'.webp';</script>"
        let images = try DingManhuaComicSource.readerImages(html: html, url: "https://www.dingmanhua.com/chapter/1-2.html")
        XCTAssertEqual(3, images.count)
        XCTAssertEqual("https://image1.dingmanhua.com/mh/book/chapter/1.webp", images[0])
        XCTAssertEqual("https://image1.dingmanhua.com/mh/book/chapter/3.webp", images[2])
        XCTAssertTrue((try DingManhuaComicSource.readerImages(html: "<img src='https://ads.invalid/a.gif'>", url: "https://www.dingmanhua.com/")).isEmpty)
        let cards = "<article class='manga-card'><a href='/comic/1.html'><img data-src='/cover.jpg'></a><div class='manga-title'>测试漫画</div></article>"
        XCTAssertEqual("测试漫画", DingManhuaComicSource.parseCards(cards).first?.title)
    }

    func testDongDirectoryExcludesNavigationAndOrdersOldestFirst() {
        let html = "<a href='/manhua/chapter/1/12/'>开始阅读</a><div class='cy_plist'><ul><li><a href='/manhua/chapter/1/12/'>第2卷</a></li><li><a href='/manhua/chapter/1/11/'>第1卷</a></li></ul></div>"
        var chapters = DongmanLaComicSource.parseChapters(comicId: "1", html: html)
        XCTAssertEqual(2, chapters.count)
        XCTAssertEqual("第1卷", chapters[0].title)
        XCTAssertEqual("第2卷", chapters[1].title)

        chapters = DongmanLaComicSource.parseChapters(comicId: "1", html: html.replacingOccurrences(of: "class='cy_plist'", with: "id='chapterList'"))
        XCTAssertEqual("第1卷", chapters[0].title)
        XCTAssertEqual("第2卷", chapters[1].title)
    }

    func testBaoziDetailIgnoresSiteHeading() {
        XCTAssertEqual("测试漫画", BaoziComicSource.parseDetailSummary("test", "<h1>包子漫画</h1><h1 class='comics-detail__title'>测试漫画</h1>").title)
    }
}
