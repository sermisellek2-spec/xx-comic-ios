import XCTest
@testable import ComicCore

final class NewPublicSourcesTests: XCTestCase {
    private static func fixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "new-sources")
                ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/new-sources")
                ?? Bundle.module.url(forResource: name, withExtension: nil) else {
            throw NSError(domain: "NewPublicSourcesTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture: \(name)"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private final class ZaiTransport: HTTPTransport, @unchecked Sendable {
        var url: String = ""
        var override: String?
        var requests: Int = 0

        func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
            self.url = url.absoluteString
            requests += 1
            let name: String
            if self.url.contains("/chapter/") {
                name = "zai-reader.json"
            } else if self.url.contains("/detail/") {
                name = "zai-detail.html"
            } else if self.url.contains("/search/") {
                name = "zai-search.html"
            } else if self.url.contains("/filter/") {
                name = "zai-category.html"
            } else {
                name = "zai-list.html"
            }
            let body = try override ?? NewPublicSourcesTests.fixture(name)
            return HTTPResponse(data: Data(body.utf8), statusCode: 200)
        }

        func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
            try await get(url, headers: headers)
        }
    }

    private final class GuaziTransport: HTTPTransport, @unchecked Sendable {
        var url: String = ""
        var override: String?
        var requests: Int = 0

        func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
            self.url = url.absoluteString
            requests += 1
            let name: String
            if self.url.contains("chapter.php") {
                name = "guazi-reader1.html"
            } else if self.url.contains("comic.php") {
                name = "guazi-top.html"
            } else {
                name = "guazi-list1.html"
            }
            let body = try override ?? NewPublicSourcesTests.fixture(name)
            return HTTPResponse(data: Data(body.utf8), statusCode: 200)
        }

        func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
            try await get(url, headers: headers)
        }
    }

    func testZaiListShapesPaginationAndFilters() async throws {
        let transport = ZaiTransport()
        let s = ZaimanhuaComicSource(transport: transport)
        let latest = try await s.latest(page: 2)
        XCTAssertFalse(latest.isEmpty)
        XCTAssertTrue(transport.url.hasSuffix("/0/2"))

        let search = try await s.search(keyword: "海贼王", page: 2)
        XCTAssertFalse(search.isEmpty)
        XCTAssertTrue(transport.url.contains("page=2"))
        XCTAssertTrue(transport.url.contains("%E6%B5%B7"))

        let category = try await s.category(filters: ["zone": "2305"], page: 2)
        XCTAssertFalse(category.isEmpty)
        XCTAssertTrue(transport.url.contains("zone=2305"))

        let parsed = try ZaimanhuaComicSource.parseList("{data:[{id:0,comic_id:7,title:'sample'}]}")
        XCTAssertEqual("zaimanhua:7", parsed.first?.comicId)
    }

    func testZaiLazyDirectoryKeepsSectionOrderAndMetadata() async throws {
        let transport = ZaiTransport()
        let s = ZaimanhuaComicSource(transport: transport)
        let d = try await s.detail(comicId: "zaimanhua:57069")
        XCTAssertTrue(d.chapters.isEmpty)
        XCTAssertFalse(d.latestChapter.isEmpty)

        let chapters = try await s.chapters(comicId: d.summary.comicId)
        XCTAssertEqual(1, transport.requests)
        XCTAssertEqual(237, chapters.count)
        for i in 1..<chapters.count {
            if chapters[i].sectionSlot == chapters[i - 1].sectionSlot {
                XCTAssertTrue(chapters[i].chapterSlot >= chapters[i - 1].chapterSlot)
            }
        }
    }

    func testZaiSignedImagesRefreshWhenRestoredOrRejected() async throws {
        let transport = ZaiTransport()
        let s = ZaimanhuaComicSource(transport: transport)
        let page = try await s.chapter(url: "https://v4api.zaimanhua.com/app/v1/comic/chapter/57069/187099?_v=2.2.5")
        let image = page.imageUrls[0]
        XCTAssertTrue(image.hasSuffix("#xx-zai=57069/187099/0"))

        let resolved1 = try await s.resolveImageUrl(image, force: false)
        XCTAssertTrue(resolved1.contains("sign=fixture"))
        XCTAssertEqual(1, transport.requests)

        _ = try await s.resolveImageUrl(image, force: true)
        XCTAssertEqual(2, transport.requests)

        let restoredTransport = ZaiTransport()
        let restored = ZaimanhuaComicSource(transport: restoredTransport)
        _ = try await restored.resolveImageUrl(image, force: false)
        XCTAssertEqual(1, restoredTransport.requests)

        XCTAssertEqual("zaimanhua:57069:187099:0", ZaimanhuaComicSource.imageCacheIdentity(image))
        XCTAssertEqual(
            ZaimanhuaComicSource.imageCacheIdentity(image),
            ZaimanhuaComicSource.imageCacheIdentity(image.replacingOccurrences(of: "sign=fixture", with: "sign=renewed"))
        )
        XCTAssertTrue(DownloadModels.sameImage(image, image.replacingOccurrences(of: "sign=fixture", with: "sign=renewed")))
    }

    func testZaiRestrictedChaptersAreNotOffered() async throws {
        let transport = ZaiTransport()
        let s = ZaimanhuaComicSource(transport: transport)
        transport.override = "{data:{data:{chapters:[{data:[{chapter_id:1,canRead:false},{chapter_id:2,is_fee:1},{chapter_id:3,canRead:true,chapter_name:'public'}]}]}}}"
        let chapters = try await s.chapters(comicId: "zaimanhua:57069")
        XCTAssertEqual(1, chapters.count)
        XCTAssertEqual("3", chapters[0].chapterId)

        transport.override = "{data:{data:{comic_id:57069,chapter_id:187099,canRead:false,page_url:['https://example.com/a.jpg']}}}"
        do {
            _ = try await s.chapter(url: chapters[0].url.replacingOccurrences(of: "/3?", with: "/187099?"))
            XCTFail("Expected restricted chapter error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("权限"))
        }
    }

    func testZaiServerErrorsAreVisible() async throws {
        let transport = ZaiTransport()
        let s = ZaimanhuaComicSource(transport: transport)
        transport.override = "{errno:403,errmsg:'denied'}"
        do {
            _ = try await s.latest(page: 1)
            XCTFail("Expected server error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("denied"))
        }
    }

    func testGuaziListsAndFilterPagingUseDesktopPages() async throws {
        let transport = GuaziTransport()
        let s = GuaziComicSource(transport: transport)
        let latest = try await s.latest(page: 2)
        XCTAssertFalse(latest.isEmpty)
        XCTAssertTrue(transport.url.contains("page=2"))
        XCTAssertTrue(s.userAgent().contains("Windows"))

        _ = try await s.search(keyword: "海贼王", page: 2)
        XCTAssertTrue(transport.url.contains("keyword=%E6%B5%B7"))

        _ = try await s.category(filters: ["city": "78"], page: 2)
        XCTAssertTrue(transport.url.contains("city=78"))
        XCTAssertTrue(transport.url.contains("page=2"))
    }

    func testGuaziLazyDirectoryIncludesOnlyFullListInReadingOrder() async throws {
        let transport = GuaziTransport()
        let s = GuaziComicSource(transport: transport)
        let d = try await s.detail(comicId: "guazi:18741")
        XCTAssertTrue(d.chapters.isEmpty)
        XCTAssertFalse(d.latestChapter.isEmpty)

        let chapters = try await s.chapters(comicId: d.summary.comicId)
        XCTAssertEqual(1, transport.requests)
        XCTAssertEqual(87, chapters.count)
        XCTAssertEqual("954976", chapters[0].chapterId)
        XCTAssertEqual("2559326", chapters[86].chapterId)

        let page = try await s.chapter(url: chapters[86].url)
        XCTAssertEqual(58, page.imageUrls.count)
    }

    func testGuaziReaderExcludesAdsAndRecommendations() async throws {
        let transport = GuaziTransport()
        let s = GuaziComicSource(transport: transport)
        transport.override = "<img src='https://ad.example/a.jpg'><section class='reader-images'><img data-src='https://cdn.example/1.webp'><img src='https://cdn.example/1.webp'><img src='/2.jpg'></section><img src='https://ad.example/b.jpg'>"
        let images = try await s.chapter(url: "https://www.guazimanhua.com/chapter.php?id=1").imageUrls
        XCTAssertEqual(["https://cdn.example/1.webp", "https://www.guazimanhua.com/2.jpg"], images)
    }

    func testGuaziEmptyDirectoryHasActionableError() async throws {
        let transport = GuaziTransport()
        let s = GuaziComicSource(transport: transport)
        transport.override = try Self.fixture("guazi-detail.html")
        do {
            _ = try await s.chapters(comicId: "guazi:37554")
            XCTFail("Expected empty directory error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("暂无可读章节"))
        }
    }

    func testSourceConfigurationsRoundTripAndKeepChapterRoutes() throws {
        let pairs: [(SourceConfigItem, SourceConfigItem)] = [
            (SourceConfigDefaults.zaimanhua(enabled: true), SourceConfigDefaults.zaimanhua(enabled: false)),
            (SourceConfigDefaults.guazi(enabled: true), SourceConfigDefaults.guazi(enabled: false))
        ]
        for (config, disabled) in pairs {
            let data = try JSONEncoder().encode(disabled)
            let saved = try JSONDecoder().decode(SourceConfigItem.self, from: data)
            XCTAssertEqual(config.id, saved.id)
            XCTAssertFalse(saved.enabled)
            XCTAssertEqual(config.route("chapter"), saved.route("chapter"))
        }
    }
}
