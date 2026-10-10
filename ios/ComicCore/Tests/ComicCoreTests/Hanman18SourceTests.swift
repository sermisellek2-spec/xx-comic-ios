import XCTest
@testable import ComicCore

final class Hanman18SourceTests: XCTestCase {
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

    func testLatestAndCardsParsingAndDeduplication() async throws {
        let html = """
        <html><body>
          <div class="list">
            <a href="https://hanman18.com/manhwa/738">
              <img src="https://azminv2.hanman18.com/uploads/manga/738/cover/cover.webp">
              <h2 class="title">復仇母女丼</h2>
            </a>
            <a href="/manhwa/738">
              <img src="/duplicate.webp">
              <h2 class="title">重复项</h2>
            </a>
            <a href="/manhwa/shechanhuazi">
              <img data-src="https://azminv2.hanman18.com/uploads/manga/shechanhuazi/cover.webp">
              <div class="story_name">社團學姊</div>
            </a>
          </div>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://hanman18.com/list-manga": response(html),
            "https://hanman18.com/list-manga/2": response(html)
        ])
        let source = Hanman18ComicSource(transport: transport)

        let latest = try await source.latest(page: 1)
        XCTAssertEqual(latest.count, 2)
        XCTAssertEqual(latest[0].comicId, "hanman18:738")
        XCTAssertEqual(latest[0].title, "復仇母女丼")
        XCTAssertEqual(latest[0].coverUrl, "https://azminv2.hanman18.com/uploads/manga/738/cover/cover.webp")

        XCTAssertEqual(latest[1].comicId, "hanman18:shechanhuazi")
        XCTAssertEqual(latest[1].title, "社團學姊")
        XCTAssertEqual(latest[1].coverUrl, "https://azminv2.hanman18.com/uploads/manga/shechanhuazi/cover.webp")

        let p2 = try await source.latest(page: 2)
        XCTAssertEqual(p2.count, 2)
    }

    func testPopularParsingFromHomepage() async throws {
        let html = """
        <html><body>
          <h5>受欢迎的</h5>
          <div class="story_item">
            <a href="https://hanman18.com/manhwa/mimijiaohua" title="秘密教學">
              <img src="https://azminv2.hanman18.com/uploads/manga/mimijiaohua/cover.webp">
            </a>
            <div class="story_name"><a href="/manhwa/mimijiaohua">秘密教學</a></div>
            <span>2 days ago</span>
          </div>
          <div class="story_item">
            <a href="https://hanman18.com/manhwa/mimijiaohua" title="秘密教學">
              <img src="duplicate.webp">
            </a>
          </div>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://hanman18.com/": response(html)
        ])
        let source = Hanman18ComicSource(transport: transport)

        let popular = try await source.category(filters: ["audience": "popular"], page: 1)
        XCTAssertEqual(popular.count, 1)
        XCTAssertTrue(popular[0].comicId.hasPrefix("hanman18:mimijiaohua"))
        XCTAssertEqual(popular[0].title, "秘密教學")
        XCTAssertEqual(popular[0].coverUrl, "https://azminv2.hanman18.com/uploads/manga/mimijiaohua/cover.webp")
        XCTAssertEqual(popular[0].subtitle, "2 days ago")
    }

    func testSearchJsonParsing() async throws {
        let json = """
        {
          "data": [
            {
              "name": "美麗新世界",
              "slug": "37925.html",
              "otherNames": "New Beautiful World"
            },
            {
              "name": "社團學姊",
              "slug": "shechanhuazi",
              "otherNames": "Club Sunbae"
            }
          ]
        }
        """
        let transport = StubTransport(responses: [
            "https://hanman18.com/search?search=%E6%96%B0%E4%B8%96%E7%95%8C": response(json)
        ])
        let source = Hanman18ComicSource(transport: transport)

        let results = try await source.search(keyword: " 新世界 ", page: 1)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].comicId.contains("37925.html"))
        XCTAssertEqual(results[0].title, "美麗新世界")
        XCTAssertEqual(results[0].subtitle, "New Beautiful World")
        XCTAssertTrue(results[1].comicId == "hanman18:shechanhuazi" || results[1].comicId == "hanman18:shechanhuazi|shetuanxuezi")
        XCTAssertEqual(results[1].title, "社團學姊")
    }

    func testDetailParsingAndCanonicalSlugResolution() async throws {
        let aliasHtml = """
        <html>
        <head>
          <link rel="canonical" href="https://hanman18.com/manhwa/meilixinshijie" />
          <meta property="og:title" content="别名过渡页" />
        </head>
        <body>过渡内容</body>
        </html>
        """
        let canonicalHtml = """
        <html>
        <head>
          <meta property="og:title" content="美麗新世界" />
          <meta property="og:image" content="https://azminv2.hanman18.com/uploads/manga/meilixinshijie/cover.webp" />
          <meta property="og:description" content="这是一部著名的韩漫作品。" />
        </head>
        <body>
          <div class="chapter_box">
            <ul>
              <li><a href="/manhwa/meilixinshijie/1" class="chapter_num">第1话</a></li>
              <li><a href="/manhwa/meilixinshijie/2" class="chapter_num">第2话</a></li>
              <li><a href="/manhwa/meilixinshijie/2" class="chapter_num">重复项</a></li>
            </ul>
          </div>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://hanman18.com/manhwa/37925.html": response(aliasHtml),
            "https://hanman18.com/manhwa/meilixinshijie": response(canonicalHtml)
        ])
        let source = Hanman18ComicSource(transport: transport)

        let detail = try await source.detail(comicId: "hanman18:37925.html|meilixinshijie")
        XCTAssertEqual(detail.summary.title, "美麗新世界")
        XCTAssertEqual(detail.summary.coverUrl, "https://azminv2.hanman18.com/uploads/manga/meilixinshijie/cover.webp")
        XCTAssertEqual(detail.description, "这是一部著名的韩漫作品。")

        let chapters = try await source.chapters(comicId: "hanman18:37925.html|meilixinshijie")
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].chapterId, "1")
        XCTAssertEqual(chapters[0].title, "第1话")
        XCTAssertEqual(chapters[0].url, "https://hanman18.com/manhwa/meilixinshijie/1")
        XCTAssertEqual(chapters[1].chapterId, "2")
        XCTAssertEqual(chapters[1].title, "第2话")
    }

    func testChapterImagesSlideTokensDecoding() async throws {
        // Base64 tokens:
        // aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc4NTI3LzAxLmpwZw== -> https://azminv2.hanman18.com/uploads/chapters/78527/01.jpg
        // aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc4NTI3LzAyLmpwZw== -> https://azminv2.hanman18.com/uploads/chapters/78527/02.jpg
        let html = """
        <html><body>
          <h1>第1话 启程</h1>
          <script>
            var slides_p_path = [
              "aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc4NTI3LzAxLmpwZw==",
              "aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc4NTI3LzAyLmpwZw=="
            ];
          </script>
        </body></html>
        """
        let transport = StubTransport(responses: [
            "https://hanman18.com/manhwa/meilixinshijie/1": response(html)
        ])
        let source = Hanman18ComicSource(transport: transport)

        let chapter = try await source.chapter(url: "/manhwa/meilixinshijie/1")
        XCTAssertEqual(chapter.title, "第1话 启程")
        XCTAssertEqual(chapter.imageUrls, [
            "https://azminv2.hanman18.com/uploads/chapters/78527/01.jpg",
            "https://azminv2.hanman18.com/uploads/chapters/78527/02.jpg"
        ])
    }

    func testMalformedResponsesThrow() async throws {
        let transport = StubTransport(responses: [
            "https://hanman18.com/list-manga": response("<html>empty</html>"),
            "https://hanman18.com/manhwa/invalid": response("<html>no og or h1</html>"),
            "https://hanman18.com/manhwa/no-images/1": response("<html>no slides</html>")
        ])
        let source = Hanman18ComicSource(transport: transport)

        do {
            _ = try await source.latest(page: 1)
            XCTFail("Should throw on empty list")
        } catch {
            XCTAssertTrue(error is Hanman18SourceError)
        }

        do {
            _ = try await source.detail(comicId: "invalid")
            XCTFail("Should throw on missing title")
        } catch {
            XCTAssertTrue(error is Hanman18SourceError)
        }

        do {
            _ = try await source.chapter(url: "/manhwa/no-images/1")
            XCTFail("Should throw on missing images")
        } catch {
            XCTAssertTrue(error is Hanman18SourceError)
        }
    }
}
