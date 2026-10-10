import XCTest
@testable import ComicCore

final class JmSourceTests: XCTestCase {
    private struct StubTransport: HTTPTransport {
        let responses: [String: HTTPResponse]
        func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
            if let resp = responses[url.absoluteString] { return resp }
            throw HTTPTransportError.invalidStatusCode(404)
        }
    }

    private func response(_ body: String, statusCode: Int = 200) -> HTTPResponse {
        HTTPResponse(data: Data(body.utf8), statusCode: statusCode, headers: ["Content-Type": "text/html; charset=utf-8"])
    }

    func testLatestAndSearchCardsParsingAndDeduplication() async throws {
        let html = """
        <html><body>
          <div class="well">
            <a href="/album/1114754/test-manga">
              <img src="/media/albums/1114754.jpg" title="测试漫画一" />
            </a>
            <a href="/album/1114754/test-manga">
              <img src="/media/albums/1114754.jpg" title="重复漫画" />
            </a>
            <a href="/album/222333/">
              <img data-original="https://cdn-msp.18comic.vip/media/albums/222333.jpg" alt="测试漫画二" />
            </a>
          </div>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://18comic.vip/albums?o=mr&page=1": response(html),
            "https://18comic.vip/search/photos?main_tag=0&search_query=%E6%B5%8B%E8%AF%95&page=2": response(html)
        ])
        let source = JmComicSource(transport: transport)

        let latest = try await source.latest(page: 1)
        XCTAssertEqual(latest.count, 2)
        XCTAssertEqual(latest[0].comicId, "jmcomic:1114754")
        XCTAssertEqual(latest[0].title, "测试漫画一")
        XCTAssertEqual(latest[0].coverUrl, "https://18comic.vip/media/albums/1114754.jpg")

        XCTAssertEqual(latest[1].comicId, "jmcomic:222333")
        XCTAssertEqual(latest[1].title, "测试漫画二")
        XCTAssertEqual(latest[1].coverUrl, "https://cdn-msp.18comic.vip/media/albums/222333.jpg")

        let search = try await source.search(keyword: " 测试 ", page: 2)
        XCTAssertEqual(search.count, 2)
    }

    func testFilterGroupsParsingAndNormalization() async throws {
        let html = """
        <html><body>
          <h4>熱門成人主題</h4>
          <ul class="btnmg">
            <li><a href="/search/photos?search_query=tag1">标签一</a></li>
            <li><a href="/albums?o=mr">全部相簿</a></li>
          </ul>
          <h4>類別</h4>
          <ul class="btnmg">
            <li><a href="/search/photos?search_query=cat1">类别一</a></li>
            <li><a href="/other/link">无效链接</a></li>
          </ul>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://18comic.vip/theme/": response(html)
        ])
        let source = JmComicSource(transport: transport)

        let groups = try await source.filterGroups()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "热门")
        XCTAssertEqual(groups[0].options.count, 3) // 全部 + tag1 + albums
        XCTAssertEqual(groups[0].options[0].label, "全部")
        XCTAssertEqual(groups[0].options[0].value, "all")
        XCTAssertEqual(groups[0].options[1].label, "标签一")
        XCTAssertEqual(groups[0].options[1].value, "/search/photos?search_query=tag1")

        XCTAssertEqual(groups[1].label, "类别")
        XCTAssertEqual(groups[1].options.count, 2) // 全部 + cat1
    }

    func testDetailParsingAndStatus() async throws {
        let html = """
        <html>
        <head>
          <meta property="og:title" content="备用标题" />
          <meta name="description" content="备用简介" />
        </head>
        <body>
          <div id="book-name"><h3>禁漫测试本子</h3></div>
          <img id="album_photo_cover" src="/media/albums/1114754.jpg" />
          <h2>敘述：这是一部精彩的漫画作品简介。</h2>
          <div class="tag-block">
            <a href="/search/photos?main_tag=2&search_query=作者A">作者A</a>
            <a href="/search/photos?main_tag=2&search_query=作者B">作者B</a>
            <a class="tag" href="/search/photos?search_query=同人">同人</a>
            <a class="tag" href="/search/photos?search_query=連載中">連載中</a>
          </div>
          <div class="episode">
            <a href="/photo/220980" data-album="220980"><h3 class="h2_series">第1话</h3></a>
          </div>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://18comic.vip/album/1114754": response(html)
        ])
        let source = JmComicSource(transport: transport)

        let detail = try await source.detail(comicId: "jmcomic:1114754")
        XCTAssertEqual(detail.summary.title, "禁漫测试本子")
        XCTAssertEqual(detail.summary.comicId, "jmcomic:1114754")
        XCTAssertEqual(detail.summary.coverUrl, "https://18comic.vip/media/albums/1114754.jpg")
        XCTAssertEqual(detail.author, "作者A / 作者B")
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.description, "这是一部精彩的漫画作品简介。")
        XCTAssertTrue(detail.summary.tags.contains("同人"))
    }

    func testChaptersParsingAndFallback() async throws {
        let htmlWithEpisodes = """
        <html><body>
          <div class="episode">
            <a href="/photo/1001" data-album="1001"><h3 class="h2_series">第1话 启程</h3></a>
            <a href="/photo/1002" data-album="1002"><h3 class="h2_series">第2话 探索</h3></a>
            <a href="/photo/1002" data-album="1002"><h3 class="h2_series">重复项</h3></a>
          </div>
        </body></html>
        """
        let htmlWithReadBlock = """
        <html><body>
          <div class="read-block">
            <a href="/photo/9999" class="btn">开始阅读</a>
          </div>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://18comic.vip/album/100": response(htmlWithEpisodes),
            "https://18comic.vip/album/200": response(htmlWithReadBlock)
        ])
        let source = JmComicSource(transport: transport)

        let chapters1 = try await source.chapters(comicId: "100")
        XCTAssertEqual(chapters1.count, 2)
        XCTAssertEqual(chapters1[0].chapterId, "1001")
        XCTAssertEqual(chapters1[0].title, "第1话 启程")
        XCTAssertEqual(chapters1[0].url, "https://18comic.vip/photo/1001")
        XCTAssertEqual(chapters1[1].chapterId, "1002")
        XCTAssertEqual(chapters1[1].title, "第2话 探索")

        let chapters2 = try await source.chapters(comicId: "200")
        XCTAssertEqual(chapters2.count, 1)
        XCTAssertEqual(chapters2[0].chapterId, "9999")
        XCTAssertEqual(chapters2[0].title, "第1话")
    }

    func testChapterImagesParsingAndScrambleID() async throws {
        let html = """
        <html><body>
          <h3 class="h2_series">第1话 启程</h3>
          <script>
            var aid = 1114754;
            var scramble_id = 220980;
            var cdnImgHost = "https://cdn-msp.18comic.vip";
            var page_arr = ["00001.jpg", "00002.webp"];
          </script>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://18comic.vip/photo/220980": response(html)
        ])
        let source = JmComicSource(transport: transport)

        let chapter = try await source.chapter(url: "/photo/220980")
        XCTAssertEqual(chapter.title, "第1话 启程")
        XCTAssertEqual(chapter.imageUrls.count, 2)
        XCTAssertEqual(chapter.imageUrls[0], "https://cdn-msp.18comic.vip/media/photos/1114754/00001.jpg?scramble_id=220980")
        XCTAssertEqual(chapter.imageUrls[1], "https://cdn-msp.18comic.vip/media/photos/1114754/00002.webp?scramble_id=220980")

        // Verify that JmImageTransform can decode slices for these image URLs!
        let slices1 = try JmImageTransform.slices(imageURL: chapter.imageUrls[0])
        XCTAssertGreaterThan(slices1, 0)
        let slices2 = try JmImageTransform.slices(imageURL: chapter.imageUrls[1])
        XCTAssertEqual(slices2, 14)
    }

    func testMalformedResponsesThrow() async throws {
        let emptyTransport = StubTransport(responses: [
            "https://18comic.vip/albums?o=mr&page=1": response("<html><body>empty</body></html>"),
            "https://18comic.vip/album/300": response("<html><body>no chapters</body></html>"),
            "https://18comic.vip/photo/400": response("<html><body>no scripts</body></html>")
        ])
        let source = JmComicSource(transport: emptyTransport)

        do {
            _ = try await source.latest(page: 1)
            XCTFail("Should throw on empty catalog")
        } catch {
            XCTAssertTrue(error is JmSourceError)
        }

        do {
            _ = try await source.chapters(comicId: "300")
            XCTFail("Should throw on missing chapters")
        } catch {
            XCTAssertTrue(error is JmSourceError)
        }

        do {
            _ = try await source.chapter(url: "/photo/400")
            XCTFail("Should throw on missing chapter parameters")
        } catch {
            XCTAssertTrue(error is JmSourceError)
        }
    }
}
