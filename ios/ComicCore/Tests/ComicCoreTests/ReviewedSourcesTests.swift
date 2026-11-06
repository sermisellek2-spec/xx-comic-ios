import XCTest
@testable import ComicCore

final class ReviewedSourcesTests: XCTestCase {
    private static let sampleUUID = "12345678-1234-1234-1234-123456789abc"

    func testMangaDexPrefersChineseAndUsesServerTotalForPaging() async throws {
        var lastUrl = ""
        let source = MangaDexComicSource { url, _, _, _, _ in
            lastUrl = url
            let body = """
            {"data":[{"id":"\(Self.sampleUUID)","attributes":{"title":{"en":"English"},"altTitles":[{"zh":"中文标题"}]},"relationships":[]}],"offset":20,"total":21}
            """
            return PublicHTTPResponse(body: body, url: url, statusCode: 200)
        }
        let rows = try await source.search(keyword: "我", page: 2)
        XCTAssertEqual(rows.first?.title, "中文标题")
        XCTAssertTrue(lastUrl.contains("offset=20"))
        XCTAssertTrue(lastUrl.contains("availableTranslatedLanguage[]=zh-hk"))
        XCTAssertFalse(source.hasMoreLastListing)
    }

    func testMangaDexFetchesEveryDirectoryPageAndOmitsExternalEnglish() async throws {
        var calls: [String] = []
        let source = MangaDexComicSource { url, _, _, _, _ in
            calls.append(url)
            let cid = url.contains("offset=0") ? Self.sampleUUID : "22345678-1234-1234-1234-123456789abc"
            let body = """
            {"total":2,"data":[{"id":"\(cid)","attributes":{"translatedLanguage":"zh","chapter":"1","externalUrl":null}}]}
            """
            return PublicHTTPResponse(body: body, url: url, statusCode: 200)
        }
        let chaps = try await source.chapters(comicId: "mangadex:\(Self.sampleUUID)")
        XCTAssertEqual(chaps.count, 2)
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].contains("offset=1"))

        let filteredSource = MangaDexComicSource { url, _, _, _, _ in
            let body = """
            {"total":2,"data":[{"id":"\(Self.sampleUUID)","attributes":{"translatedLanguage":"en"}},{"id":"\(Self.sampleUUID)","attributes":{"translatedLanguage":"zh","externalUrl":"https://other.example/"}}]}
            """
            return PublicHTTPResponse(body: body, url: url, statusCode: 200)
        }
        do {
            _ = try await filteredSource.chapters(comicId: "mangadex:\(Self.sampleUUID)")
            XCTFail("Expected error when no Chinese non-external chapters exist")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("中文章节"))
        }
    }

    func testMangaDexDoesNotReturnATruncatedCatalog() async {
        let source = MangaDexComicSource { url, _, _, _, _ in
            PublicHTTPResponse(body: #"{"total":5,"data":[]}"#, url: url, statusCode: 200)
        }
        do {
            _ = try await source.chapters(comicId: "mangadex:\(Self.sampleUUID)")
            XCTFail("Expected truncated catalog error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("中断"))
        }
    }

    func testXcomicSkipsNullAuthorNodesAndRetainsEditionId() async throws {
        let source = XcomicComicSource { url, method, _, _, json in
            XCTAssertEqual(method, "POST")
            XCTAssertTrue(json)
            let body = """
            {"data":{"get_comicNode":{"data":{"id":"edition1","name":"中文","translatedLanguage":"zh","authorNodes":[{"data":null}],"summary":{"text":"简介"}}}}}
            """
            return PublicHTTPResponse(body: body, url: url, statusCode: 200)
        }
        let d = try await source.detail(comicId: "xcomic:edition1")
        XCTAssertEqual(d.summary.comicId, "xcomic:edition1")
        XCTAssertEqual(d.author, "")
        XCTAssertEqual(d.description, "简介")
    }

    func testXcomicChineseEditionFilterAndWordAreConsumed() async throws {
        var sentBody = ""
        let source = XcomicComicSource { url, _, body, _, _ in
            sentBody = body ?? ""
            let resp = """
            {"data":{"items":[{"data":{"name":"标题","urlCover":"/c.webp"},"comicNodes":[{"data":{"id":"zh1","name":"中文版","translatedLanguage":"zh","chaps_normal":3}},{"data":{"id":"en1","name":"English","translatedLanguage":"en","chaps_normal":3}}]}]}}
            """
            return PublicHTTPResponse(body: resp, url: url, statusCode: 200)
        }
        let rows = try await source.search(keyword: "我", page: 2)
        XCTAssertEqual(rows.first?.comicId, "xcomic:zh1")
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sentBody.utf8)) as? [String: Any])
        let vars = try XCTUnwrap(parsed["variables"] as? [String: Any])
        let select = try XCTUnwrap(vars["select"] as? [String: Any])
        XCTAssertEqual(select["page"] as? Int, 2)
        XCTAssertEqual(select["word"] as? String, "我")
        XCTAssertEqual((select["incTLangs"] as? [String])?.first, "zh")

        let errorSource = XcomicComicSource { url, _, _, _, _ in
            PublicHTTPResponse(body: #"{"errors":[{"message":"busy"}],"data":null}"#, url: url, statusCode: 200)
        }
        do {
            _ = try await errorSource.search(keyword: "我", page: 1)
            XCTFail("Expected busy error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("稍后"))
        }
    }

    func testGalleryExtractsOnlyImglistAndDoesNotMixAds() throws {
        let html = #"<script>var ad=\"//ads.example/a.jpg\";var imglist = [{url:fast_img_host+\"//img.example/1.webp\",caption:\"1\"},{url:fast_img_host+\"//img.example/2.webp\"}];</script>"#
        let urls = try GalleryComicSource.wnImages(html)
        XCTAssertEqual(urls, ["https://img.example/1.webp", "https://img.example/2.webp"])
        XCTAssertThrowsError(try GalleryComicSource.wnImages("<img src='https://ads.example/a.jpg'>"))
    }

    func testGalleriesHaveOneStableRealChapter() async throws {
        for id in ["wnacg", "nhentai"] {
            let s = GalleryComicSource(config: GalleryComicSource.defaultConfig(id: id))
            let c = try await s.chapters(comicId: "\(id):123")
            XCTAssertEqual(c.count, 1)
            XCTAssertEqual(c[0].chapterId, "123")
        }
    }

    func testWnMobileDetailNormalizesFourSlashCover() async throws {
        let s = GalleryComicSource(config: GalleryComicSource.defaultConfig(id: "wnacg")) { url, _, _, _, _ in
            PublicHTTPResponse(body: "<div id='comicName'>中文画册</div><div id='Cover'><img src='////images.example/1.webp'></div>", url: url, statusCode: 200)
        }
        let d = try await s.detail(comicId: "wnacg:123")
        XCTAssertEqual(d.summary.title, "中文画册")
        XCTAssertEqual(PublicSourceImages.strip(d.summary.coverUrl), "https://images.example/1.webp")
    }

    func testSourceVpnPolicyMatchesExpectedSources() {
        XCTAssertTrue(SourceVpnPolicy.requiresVpn(sourceId: "mangadex"))
        XCTAssertTrue(SourceVpnPolicy.requiresVpn(sourceId: "xcomic"))
        XCTAssertTrue(SourceVpnPolicy.requiresVpn(sourceId: "nhentai"))
        XCTAssertFalse(SourceVpnPolicy.requiresVpn(sourceId: "kalamanhua"))
    }
}
